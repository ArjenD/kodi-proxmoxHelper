#!/usr/bin/env bash
set -euo pipefail

APP="kodi-omega"
VMID=$(pvesh get /cluster/nextid)
VMNAME="kodi-omega"
MEMORY=4096
CORES=4
DISK=32G
BRIDGE="vmbr0"
STORAGE="local-zfs"
IMG_DIR="/var/lib/vz/template/iso"
IMG="${IMG_DIR}/debian-12-genericcloud-amd64.qcow2"
SNIPPETS="/var/lib/vz/snippets"

echo "=== Kodi Omega VM helper ==="

command -v qm >/dev/null || { echo "Run on Proxmox host"; exit 1; }

mkdir -p "$IMG_DIR" "$SNIPPETS"

echo "[1/7] Download Debian 12 cloud image"
if [ ! -f "$IMG" ]; then
  wget -q --show-progress \
    -O "$IMG" \
    https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
fi

echo "[2/7] Create VM $VMID"
qm create $VMID \
  --name $VMNAME \
  --memory $MEMORY \
  --cores $CORES \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge=$BRIDGE \
  --vga virtio \
  --serial0 socket

qm set $VMID --efidisk0 $STORAGE:1,efitype=4m
qm set $VMID --scsihw virtio-scsi-pci
qm set $VMID --scsi0 $STORAGE:0,import-from=$IMG
qm resize $VMID scsi0 $DISK
qm set $VMID --boot order=scsi0

echo "[3/7] Cloud-init config"
qm set $VMID --ide2 $STORAGE:cloudinit
qm set $VMID --ipconfig0 ip=dhcp
qm set $VMID --ciuser kodi
qm set $VMID --cipassword kodi

echo "[4/7] Inject Kodi Omega installer"
cat <<'EOF' > ${SNIPPETS}/kodi-omega-vm-install.sh
#!/usr/bin/env bash
set -euo pipefail

echo "[Kodi Omega] First boot installer"

apt-get update
apt-get upgrade -y

apt-get install -y \
  curl gnupg sudo \
  xserver-xorg xinit dbus-x11 \
  lightdm \
  mesa-va-drivers intel-media-va-driver \
  alsa-utils pipewire pipewire-audio

wget -qO- https://apt.kodi.tv/repo-key.gpg \
 | gpg --dearmor > /usr/share/keyrings/kodi.gpg

echo "deb [signed-by=/usr/share/keyrings/kodi.gpg] https://apt.kodi.tv stable main" \
 > /etc/apt/sources.list.d/kodi.list

apt-get update
apt-get install -y kodi kodi-peripheral-joystick || true

useradd -m kodi || true
usermod -aG audio,video,render,input kodi

groupadd -f autologin
usermod -aG autologin kodi

cat <<EOT >/etc/lightdm/lightdm.conf.d/50-kodi.conf
[Seat:*]
autologin-user=kodi
autologin-session=kodi
EOT

cat <<EOT >/usr/share/xsessions/kodi.desktop
[Desktop Entry]
Name=Kodi
Exec=kodi-standalone
Type=Application
EOT

systemctl enable lightdm
systemctl set-default graphical.target

apt-get autoremove -y
apt-get autoclean

echo "[Kodi Omega] Install complete"
EOF

chmod +x ${SNIPPETS}/kodi-omega-vm-install.sh

qm set $VMID --cicustom "user=local:snippets/kodi-omega-vm-install.sh"

echo "[5/7] Start VM"
qm start $VMID

echo
echo "✅ Kodi Omega VM created"
echo "➡ VMID: $VMID"
echo "➡ Login: kodi / kodi"
echo "➡ Boots straight into Kodi"
