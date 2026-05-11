#!/bin/bash
source configs/build.env
set -e

echo "[*] Assembling Disk Image ($IMG_NAME)..."

dd if=/dev/zero of=$IMG_NAME bs=1M count=$DISK_SIZE_MB status=none
parted -s $IMG_NAME mklabel gpt
parted -s $IMG_NAME mkpart ESP fat32 1MiB 50MiB
parted -s $IMG_NAME set 1 esp on
parted -s $IMG_NAME mkpart primary ext4 50MiB 100%

LOOP=$(sudo losetup -Pf --show $IMG_NAME)
trap 'sudo umount $OUT_DIR/mnt_efi $OUT_DIR/mnt_root 2>/dev/null || true; sudo losetup -d $LOOP 2>/dev/null || true' EXIT

sudo mkfs.fat -F 32 ${LOOP}p1 >/dev/null
sudo mkfs.ext4 -F ${LOOP}p2 >/dev/null 2>&1

mkdir -p $OUT_DIR/mnt_efi $OUT_DIR/mnt_root
sudo mount ${LOOP}p1 $OUT_DIR/mnt_efi
sudo mount ${LOOP}p2 $OUT_DIR/mnt_root

echo "[*] Installing Base OS to Root Partition..."
sudo mkdir -p $OUT_DIR/mnt_root/{bin,sbin,dev,proc,sys,tmp,etc,root,mnt,var/lib,var/cache}

sudo cp $TOYBOX_SRC/toybox $OUT_DIR/mnt_root/bin/
sudo bash -c "cd $OUT_DIR/mnt_root/bin && for cmd in \$(./toybox); do ln -s toybox \$cmd; done"

sudo cp $OUT_DIR/horizon $OUT_DIR/mnt_root/sbin/init
sudo mkdir -p $OUT_DIR/mnt_root/etc/horizon/services
sudo cp $CONFIG_DIR/network.service $OUT_DIR/mnt_root/etc/horizon/services/
sudo cp $CONFIG_DIR/shell.service $OUT_DIR/mnt_root/etc/horizon/services/

echo "[*] Injecting Blackhole Package Manager (bhpkg)..."
if [ -f "$SRC_DIR/bhpkg/bhpkg" ]; then
    sudo cp $SRC_DIR/bhpkg/bhpkg $OUT_DIR/mnt_root/bin/
    sudo chmod +x $OUT_DIR/mnt_root/bin/bhpkg
fi

sudo cp $CONFIG_DIR/dhcp.script $OUT_DIR/mnt_root/bin/dhcp.script
sudo chmod +x $OUT_DIR/mnt_root/bin/dhcp.script

echo "[*] Installing Kernel to EFI Bootloader..."
sudo mkdir -p $OUT_DIR/mnt_efi/EFI/BOOT
sudo cp $OUT_DIR/BOOTX64.EFI $OUT_DIR/mnt_efi/EFI/BOOT/BOOTX64.EFI

echo "[*] Cleaning up mounts..."
sudo umount $OUT_DIR/mnt_efi $OUT_DIR/mnt_root
sudo losetup -d $LOOP
trap - EXIT

echo "[+] Disk Image complete: $IMG_NAME"