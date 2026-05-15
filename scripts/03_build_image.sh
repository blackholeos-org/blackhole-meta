#!/bin/bash
source configs/build.env
set -e

echo "[*] Assembling Disk Image ($IMG_NAME)..."

dd if=/dev/zero of=$IMG_NAME bs=1M count=$DISK_SIZE_MB status=none

sfdisk $IMG_NAME <<EOF
label: gpt
1: size=50M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=ESP
2: type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=8b056c80-db81-4203-aa99-275d27575293, name=ROOT
EOF

LOOP=$(sudo losetup -Pf --show $IMG_NAME)
trap 'sudo umount $OUT_DIR/mnt_efi $OUT_DIR/mnt_root 2>/dev/null || true; sudo losetup -d $LOOP 2>/dev/null || true' EXIT

sudo mkfs.fat -F 32 ${LOOP}p1 >/dev/null
sudo mkfs.ext4 -F ${LOOP}p2 >/dev/null 2>&1

mkdir -p $OUT_DIR/mnt_efi $OUT_DIR/mnt_root
sudo mount ${LOOP}p1 $OUT_DIR/mnt_efi
sudo mount ${LOOP}p2 $OUT_DIR/mnt_root

echo "[*] Installing Base OS to Root Partition..."
sudo mkdir -p $OUT_DIR/mnt_root/{bin,sbin,dev,proc,sys,tmp,etc/ssl/certs,etc/horizon/services,root,mnt,var/lib,var/cache,var/log,home}
sudo chmod 755 $OUT_DIR/mnt_root/home

echo "[*] Setting up MDEV configuration..."
cat << 'EOF' | sudo tee $OUT_DIR/mnt_root/etc/mdev.conf >/dev/null
null        root:root 0666
zero        root:root 0666
full        root:root 0666
random      root:root 0666
urandom     root:root 0666
console     root:tty  0600
tty         root:tty  0666
tty[0-9]*   root:tty  0660
ttyS[0-9]*  root:tty  0660
ptmx        root:tty  0666
EOF

echo "[*] Creating /etc/fstab..."
cat << 'EOF' | sudo tee $OUT_DIR/mnt_root/etc/fstab >/dev/null
# /etc/fstab: static file system information
# <file system> <dir>   <type>   <options>                      <dump> <pass>
/dev/sda2       /       ext4     rw,noatime,errors=remount-ro   0      1
proc            /proc   proc     defaults                       0      0
sysfs           /sys    sysfs    defaults                       0      0
devtmpfs        /dev    devtmpfs defaults                       0      0
tmpfs           /tmp    tmpfs    defaults,nosuid,nodev          0      0
tmpfs           /run    tmpfs    defaults,nosuid,nodev          0      0
EOF

echo "[*] Establishing System Logging Services..."
cat << 'EOF' | sudo tee $OUT_DIR/mnt_root/etc/horizon/services/syslogd.service >/dev/null
[Service]
Exec=/bin/syslogd -n -O /var/log/messages
Respawn=true
User=root
Group=root
EOF

cat << 'EOF' | sudo tee $OUT_DIR/mnt_root/etc/horizon/services/klogd.service >/dev/null
[Service]
Exec=/bin/klogd -n
Respawn=true
User=root
Group=root
EOF

cat << 'EOF' | sudo tee $OUT_DIR/mnt_root/etc/horizon/services/getty-tty1.service >/dev/null
[Service]
Exec=/bin/getty 38400 tty1 linux
Respawn=true
User=root
Group=root
EOF

echo -e "\n=========================================" | sudo tee $OUT_DIR/mnt_root/etc/issue >/dev/null
echo -e "   Welcome to Blackhole OS" | sudo tee -a $OUT_DIR/mnt_root/etc/issue >/dev/null
echo -e "=========================================\n" | sudo tee -a $OUT_DIR/mnt_root/etc/issue >/dev/null

echo "root:x:0:0:root:/root:/bin/sh" | sudo tee $OUT_DIR/mnt_root/etc/passwd >/dev/null
echo "nobody:x:65534:65534:nobody:/tmp:/bin/false" | sudo tee -a $OUT_DIR/mnt_root/etc/passwd >/dev/null

echo "root:x:0:" | sudo tee $OUT_DIR/mnt_root/etc/group >/dev/null
echo "tty:x:5:" | sudo tee -a $OUT_DIR/mnt_root/etc/group >/dev/null
echo "nobody:x:65534:" | sudo tee -a $OUT_DIR/mnt_root/etc/group >/dev/null
echo "/bin/sh" | sudo tee $OUT_DIR/mnt_root/etc/shells >/dev/null

HASH=$(openssl passwd -6 "root")
echo "root:${HASH}:19000:0:99999:7:::" | sudo tee $OUT_DIR/mnt_root/etc/shadow >/dev/null
echo "nobody:*:19000:0:99999:7:::" | sudo tee -a $OUT_DIR/mnt_root/etc/shadow >/dev/null
sudo chmod 600 $OUT_DIR/mnt_root/etc/shadow

sudo cp $BUSYBOX_SRC/busybox $OUT_DIR/mnt_root/bin/
sudo bash -c "cd $OUT_DIR/mnt_root/bin && for cmd in \$(./busybox --list); do ln -sf busybox \$cmd; done"

sudo cp $OUT_DIR/horizon $OUT_DIR/mnt_root/sbin/init
sudo cp $CONFIG_DIR/network.service $OUT_DIR/mnt_root/etc/horizon/services/
sudo cp $CONFIG_DIR/getty.service $OUT_DIR/mnt_root/etc/horizon/services/

echo "[*] Injecting Security CA Certificates..."
sudo cp $OUT_DIR/rootfs/etc/ssl/certs/ca-certificates.crt $OUT_DIR/mnt_root/etc/ssl/certs/
sudo ln -s ca-certificates.crt $OUT_DIR/mnt_root/etc/ssl/certs/cert.pem

echo "[*] Injecting Blackhole Package Manager (bhpkg)..."
if [ -f "$SRC_DIR/bhpkg/bhpkg" ]; then
    sudo cp $SRC_DIR/bhpkg/bhpkg $OUT_DIR/mnt_root/bin/
    sudo chmod +x $OUT_DIR/mnt_root/bin/bhpkg
fi

sudo mkdir -p $OUT_DIR/mnt_root/etc/bhpkg
sudo cp $CONFIG_DIR/bhpkg.conf $OUT_DIR/mnt_root/etc/bhpkg/bhpkg.conf
sudo cp $CONFIG_DIR/keys/repo-pub.pem $OUT_DIR/mnt_root/etc/bhpkg/repo-pub.pem

sudo cp $CONFIG_DIR/dhcp.script $OUT_DIR/mnt_root/bin/dhcp.script
sudo chmod +x $OUT_DIR/mnt_root/bin/dhcp.script

echo "[*] Installing Cron (bh-crond)..."
sudo cp $OUT_DIR/bh-crond $OUT_DIR/mnt_root/sbin/
sudo chmod +x $OUT_DIR/mnt_root/sbin/bh-crond

sudo cp $CONFIG_DIR/crontab $OUT_DIR/mnt_root/etc/crontab
sudo chmod 644 $OUT_DIR/mnt_root/etc/crontab
sudo cp $CONFIG_DIR/cron.service $OUT_DIR/mnt_root/etc/horizon/services/

echo "[*] Installing Kernel to EFI Bootloader..."
sudo mkdir -p $OUT_DIR/mnt_efi/EFI/BOOT
sudo cp $OUT_DIR/BOOTX64.EFI $OUT_DIR/mnt_efi/EFI/BOOT/BOOTX64.EFI

echo "[*] Cleaning up mounts..."
sudo umount $OUT_DIR/mnt_efi $OUT_DIR/mnt_root
sudo losetup -d $LOOP
trap - EXIT

echo "[+] Disk Image complete: $IMG_NAME"