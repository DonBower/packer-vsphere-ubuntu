#cloud-config

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Ubuntu Server 24.04 LTS

autoinstall:
  version: 1
  apt:
    geoip: true
    preserve_sources_list: false
    primary:
      - arches: [amd64, i386]
        uri: http://archive.ubuntu.com/ubuntu
      - arches: [default]
        uri: http://ports.ubuntu.com/ubuntu-ports
  early-commands:
    - sudo systemctl stop ssh
  locale: ${vm_guest_os_language}
  keyboard:
    layout: ${vm_guest_os_keyboard}
  storage:
    config:
      - type: disk
        id: disk-sda
        path: /dev/sda
        ptable: gpt
        wipe: superblock

      - type: partition
        id: partition-0
        device: disk-sda
        number: 1
        size: 512M
        wipe: superblock
        flag: boot
        grub_device: true

      - type: partition
        id: partition-1
        device: disk-sda
        number: 2
        size: 1024M
        wipe: superblock

      - type: partition
        id: partition-2
        device: disk-sda
        number: 3
        size: -1
        wipe: superblock

      - type: format
        id: format-efi
        volume: partition-0
        fstype: fat32
        label: EFIFS

      - type: format
        id: format-boot
        volume: partition-1
        fstype: xfs
        label: BOOTFS

      - type: lvm_volgroup
        id: lvm_volgroup-0
        devices:
          - partition-2
        name: sysvg

      - type: lvm_partition
        id: lvm_partition-root
        volgroup: lvm_volgroup-0
        name: root
        size: 8192M
        wipe: superblock

      - type: lvm_partition
        id: lvm_partition-home
        volgroup: lvm_volgroup-0
        name: home
        size: 512M
        wipe: superblock
      
      - type: lvm_partition
        id: lvm_partition-opt
        volgroup: lvm_volgroup-0
        name: opt
        size: 512M
        wipe: superblock
      
      - type: lvm_partition
        id: lvm_partition-tmp
        volgroup: lvm_volgroup-0
        name: tmp
        size: 1024M
        wipe: superblock

      - type: format
        id: format-root
        volume: lvm_partition-root
        fstype: xfs
        label: ROOTFS

      - type: format
        id: format-home
        volume: lvm_partition-home
        fstype: xfs
        label: HOMEFS
      
      - type: format
        id: format-opt
        volume: lvm_partition-opt
        fstype: xfs
        label: OPTFS

      - type: format
        id: format-tmp
        volume: lvm_partition-tmp
        fstype: xfs
        label: TMPFS

      - type: lvm_partition
        id: lvm_partition-var
        volgroup: lvm_volgroup-0
        name: var
        size: 2048M
        wipe: superblock

      - type: format
        id: format-var
        volume: lvm_partition-var
        fstype: xfs
        label: VARFS

      - type: lvm_partition
        id: lvm_partition-log
        volgroup: lvm_volgroup-0
        name: log
        size: 512M
        wipe: superblock

      - type: format
        id: format-log
        volume: lvm_partition-log
        fstype: xfs
        label: LOGFS

      - type: lvm_partition
        id: lvm_partition-audit
        volgroup: lvm_volgroup-0
        name: audit
        size: 512M
        wipe: superblock

      - type: format
        id: format-audit
        volume: lvm_partition-audit
        fstype: xfs
        label: AUDITFS

      - type: mount
        id: mount-root
        device: format-root
        path: /

      - type: mount
        id: mount-boot
        device: format-boot
        path: /boot

      - type: mount
        id: mount-efi
        device: format-efi
        path: /boot/efi

      - type: mount
        id: mount-home
        device: format-home
        path: /home

      - type: mount
        id: mount-opt
        device: format-opt
        path: /opt

      - type: mount
        id: mount-tmp
        device: format-tmp
        path: /tmp

      - type: mount
        id: mount-var
        device: format-var
        path: /var

      - type: mount
        id: mount-log
        device: format-log
        path: /var/log

      - type: mount
        id: mount-audit
        device: format-audit
        path: /var/audit

  identity:
    hostname: ubuntu-server
    username: ${build_username}
    password: ${build_password_encrypted}
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
    - open-vm-tools
    - cloud-init
  user-data:
    disable_root: false
    timezone: ${vm_guest_os_timezone}
  late-commands:
    - sed -i -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /target/etc/ssh/sshd_config
    - echo '${build_username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${build_username}
    - curtin in-target --target=/target -- chmod 440 /etc/sudoers.d/${build_username}
