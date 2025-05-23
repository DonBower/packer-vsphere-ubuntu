/*
    DESCRIPTION:
    Ubuntu Server 22.04 LTS template using the Packer Builder for VMware vSphere (vsphere-iso).
*/

//  BLOCK: packer
//  The Packer configuration.

packer {
  required_version = ">= 1.9.1"
  required_plugins {
    git = {
      version = ">= 0.4.2"
      source  = "github.com/ethanmdavidson/git"
    }
    vsphere = {
      version = ">= v1.2.0"
      source  = "github.com/hashicorp/vsphere"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
  }
}

//  BLOCK: data
//  Defines the data sources.

data "git-repository" "cwd" {}
data "git-commit" "cwd-head" {}

//  BLOCK: locals
//  Defines the local variables.

locals {
  config            = yamldecode(file("${path.root}/data/config.yaml"))
  isoConfig         = local.config.iso
  vmConfig          = local.config.vm
  diskConfig        = local.config.disk
  lvmConfig         = local.config.lvm
  build_by          = "Built by: HashiCorp Packer ${packer.version}"
  build_author      = data.git-commit.cwd-head.author
  build_date        = formatdate("YYYY-MM-DD", timestamp())
  build_time        = formatdate("hh:mm ZZZ", timestamp())
  build_branch      = data.git-repository.cwd.head
  build_commit      = substr(data.git-commit.cwd-head.hash, 0, 8)
  version_text      = file("${abspath(path.root)}/version.txt")
  build_version     = data.git-repository.cwd.head == "main" ? "${local.version_text}" : "${local.version_text}-rc"
  build_description = "Version: ${local.build_version}\nBuilt on: ${local.build_date}\n${local.build_by}\n${local.build_author}"
  iso_paths         = ["[${var.common_iso_datastore}] ${local.isoConfig.path}/${local.isoConfig.file}"]
  # iso_paths         = ["/Volumes/isostore/linux/ubuntu/${local.isoConfig.file}"]
  iso_checksum      = "${local.isoConfig.checksum.type}:${local.isoConfig.checksum.value}"
  manifest_date     = formatdate("YYYY-MM-DD hh:mm:ss", timestamp())
  manifest_path     = "${path.cwd}/manifests/"
  manifest_output   = "${local.manifest_path}${local.manifest_date}.json"
  ovf_export_path   = "${path.cwd}/artifacts/${local.vm_name}"
  data_source_content = {
    "/meta-data" = file("${abspath(path.root)}/data/meta-data")
    "/user-data" = templatefile("${abspath(path.root)}/data/user-data.pkrtpl.hcl", {
      build_username           = var.build_username
      build_password           = var.build_password
      build_password_encrypted = var.build_password_encrypted
      vm_guest_os_language     = var.vm_guest_os_language
      vm_guest_os_keyboard     = var.vm_guest_os_keyboard
      vm_guest_os_timezone     = var.vm_guest_os_timezone
      diskConfig               = local.diskConfig
      lvmConfig                = local.lvmConfig
    })
  }
  data_source_command = var.common_data_source == "http" ? "ds=\"nocloud-net;seedfrom=http://{{.HTTPIP}}:{{.HTTPPort}}/\"" : "ds=\"nocloud\""
  vm_name             = "${var.vm_guest_os_name}-${var.vm_guest_os_version}-${local.build_version}"
  bucket_name         = replace("${var.vm_guest_os_family}-${var.vm_guest_os_name}-${var.vm_guest_os_version}", ".", "")
  bucket_description  = "${var.vm_guest_os_family} ${var.vm_guest_os_name} ${var.vm_guest_os_version}"
}

//  BLOCK: source
//  Defines the builder configuration blocks.

source "file" "ubuntu-iso-file" {
  source =  "/Volumes/isostore/linux/ubuntu/${local.isoConfig.file}"
  target =  "dummy_artifact"
}

source "vsphere-iso" "linux-ubuntu" {

  // vCenter Server Endpoint Settings and Credentials
  vcenter_server      = var.vsphere_endpoint
  username            = var.vsphere_username
  password            = var.vsphere_password
  insecure_connection = var.vsphere_insecure_connection

  // vSphere Settings
  datacenter = var.vsphere_datacenter
  cluster    = var.vsphere_cluster
  datastore  = var.vsphere_datastore
  folder     = var.vsphere_folder

  // Virtual Machine Settings
  vm_name              = local.vm_name
  guest_os_type        = var.vm_guest_os_type
  firmware             = var.vm_firmware
  CPUs                 = var.vm_cpu_count
  cpu_cores            = var.vm_cpu_cores
  CPU_hot_plug         = var.vm_cpu_hot_add
  RAM                  = var.vm_mem_size
  RAM_hot_plug         = var.vm_mem_hot_add
  cdrom_type           = var.vm_cdrom_type
  disk_controller_type = var.vm_disk_controller_type
  dynamic "storage" {
    for_each = local.diskConfig
    content {
      disk_size             = storage.value.size
      disk_thin_provisioned = storage.value.thin
      disk_eagerly_scrub    = storage.value.eager
      disk_controller_index = storage.value.controller
    }
  }
  network_adapters {
    network      = var.vsphere_network
    network_card = var.vm_network_card
  }
  vm_version           = var.common_vm_version
  remove_cdrom         = var.common_remove_cdrom
  tools_upgrade_policy = var.common_tools_upgrade_policy
  notes                = local.build_description

  // Removable Media Settings
  iso_paths    = local.iso_paths
  iso_checksum = local.iso_checksum
  http_content = var.common_data_source == "http" ? local.data_source_content : null
  cd_content   = var.common_data_source == "disk" ? local.data_source_content : null
  cd_label     = var.common_data_source == "disk" ? "cidata" : null

  // Boot and Provisioning Settings
  http_ip       = var.common_data_source == "http" ? var.common_http_ip : null
  http_port_min = var.common_data_source == "http" ? var.common_http_port_min : null
  http_port_max = var.common_data_source == "http" ? var.common_http_port_max : null
  boot_order    = var.vm_boot_order
  boot_wait     = var.vm_boot_wait
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ${local.data_source_command}",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot",
    "<enter>"
  ]
  ip_wait_timeout  = var.common_ip_wait_timeout
  shutdown_command = "echo '${var.build_password}' | sudo -S -E shutdown -P now"
  shutdown_timeout = var.common_shutdown_timeout

  // Communicator Settings and Credentials
  communicator       = "ssh"
  ssh_proxy_host     = var.communicator_proxy_host
  ssh_proxy_port     = var.communicator_proxy_port
  ssh_proxy_username = var.communicator_proxy_username
  ssh_proxy_password = var.communicator_proxy_password
  ssh_username       = var.build_username
  ssh_password       = var.build_password
  ssh_port           = var.communicator_port
  ssh_timeout        = var.communicator_timeout

  // Template and Content Library Settings
  convert_to_template = var.common_template_conversion
  dynamic "content_library_destination" {
    for_each = var.common_content_library_name != null ? [1] : []
    content {
      library     = var.common_content_library_name
      description = local.build_description
      ovf         = var.common_content_library_ovf
      destroy     = var.common_content_library_destroy
      skip_import = var.common_content_library_skip_export
    }
  }

  // OVF Export Settings
  dynamic "export" {
    for_each = var.common_ovf_export_enabled == true ? [1] : []
    content {
      name  = local.vm_name
      force = var.common_ovf_export_overwrite
      options = [
        "extraconfig"
      ]
      output_directory = local.ovf_export_path
    }
  }
}

//  BLOCK: build
//  Defines the builders to run, provisioners, and post-processors.

build {
  sources = ["source.vsphere-iso.linux-ubuntu"]

  provisioner "ansible" {
    user          = var.build_username
    playbook_file = "${path.cwd}/ansible/main.yaml"
    roles_path    = "${path.cwd}/ansible/roles"
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${path.cwd}/ansible/ansible.cfg"
    ]
    extra_arguments = [
      "--extra-vars", "display_skipped_hosts=false",
      "--extra-vars", "BUILD_USERNAME=${var.build_username}",
      "--extra-vars", "BUILD_SECRET='${var.build_key}'",
      "--extra-vars", "ANSIBLE_USERNAME=${var.ansible_username}",
      "--extra-vars", "ANSIBLE_SECRET='${var.ansible_key}'",
    ]
  }

  post-processor "manifest" {
    output     = local.manifest_output
    strip_path = true
    strip_time = true
    custom_data = {
      ansible_username         = var.ansible_username
      build_username           = var.build_username
      build_date               = local.build_date
      build_version            = local.build_version
      common_data_source       = var.common_data_source
      common_vm_version        = var.common_vm_version
      vm_cpu_cores             = var.vm_cpu_cores
      vm_cpu_count             = var.vm_cpu_count
      vm_disk_size             = var.vm_disk_size
      vm_disk_thin_provisioned = var.vm_disk_thin_provisioned
      vm_firmware              = var.vm_firmware
      vm_guest_os_type         = var.vm_guest_os_type
      vm_mem_size              = var.vm_mem_size
      vm_network_card          = var.vm_network_card
      vsphere_cluster          = var.vsphere_cluster
      vsphere_datacenter       = var.vsphere_datacenter
      vsphere_datastore        = var.vsphere_datastore
      vsphere_endpoint         = var.vsphere_endpoint
      vsphere_folder           = var.vsphere_folder
    }
  }

  post-processor "vsphere-template" {
    host                = var.vsphere_endpoint
    username            = var.vsphere_username
    password            = var.vsphere_password
    # insecure_connection = var.vsphere_insecure_connection
    datacenter          = var.vsphere_datacenter
    # vm_name             = local.vm_name
    folder              = var.vsphere_folder
    # library             = var.common_content_library_name
  }


  # dynamic "hcp_packer_registry" {
  #   for_each = var.common_hcp_packer_registry_enabled ? [1] : []
  #   content {
  #     bucket_name = local.bucket_name
  #     description = local.bucket_description
  #     bucket_labels = {
  #       "os_family" : var.vm_guest_os_family,
  #       "os_name" : var.vm_guest_os_name,
  #       "os_version" : var.vm_guest_os_version,
  #     }
  #     build_labels = {
  #       "build_version" : local.build_version,
  #       "packer_version" : packer.version,
  #     }
  #   }
  # }
}
