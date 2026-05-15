#!/bin/bash
source configs/build.env
set -e

echo "[*] Processing Linux Kernel (v${KERNEL_VER})..."

if [ ! -d "$KERNEL_SRC" ]; then
    echo "    -> Downloading Kernel source..."
    wget -q --show-progress "$KERNEL_URL" -O /tmp/kernel.tar.xz
    echo "    -> Extracting..."
    tar -xf /tmp/kernel.tar.xz -C $SRC_DIR
    rm /tmp/kernel.tar.xz
fi

cd $KERNEL_SRC

cp $CONFIG_DIR/kernel.config .config
./scripts/config --set-str INITRAMFS_SOURCE "$OUT_DIR/rootfs.cpio.gz"

./scripts/config --enable CONFIG_NETDEVICES
./scripts/config --enable CONFIG_ETHERNET
./scripts/config --enable CONFIG_NET_VENDOR_INTEL
./scripts/config --enable CONFIG_E1000
./scripts/config --enable CONFIG_E1000E
./scripts/config --enable CONFIG_NET_VENDOR_REALTEK
./scripts/config --enable CONFIG_R8169
./scripts/config --enable CONFIG_VIRTIO_NET
./scripts/config --enable CONFIG_PACKET

./scripts/config --enable CONFIG_BLK_DEV_NVME
./scripts/config --enable CONFIG_SATA_AHCI
./scripts/config --enable CONFIG_USB_STORAGE
./scripts/config --enable CONFIG_USB_UAS

./scripts/config --enable CONFIG_USB
./scripts/config --enable CONFIG_USB_XHCI_HCD
./scripts/config --enable CONFIG_USB_EHCI_HCD
./scripts/config --enable CONFIG_HID_GENERIC
./scripts/config --enable CONFIG_USB_HID

./scripts/config --enable CONFIG_FB
./scripts/config --enable CONFIG_FB_EFI
./scripts/config --enable CONFIG_DRM
./scripts/config --enable CONFIG_DRM_SIMPLEDRM
./scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE

./scripts/config --enable CONFIG_DEVTMPFS
./scripts/config --enable CONFIG_DEVTMPFS_MOUNT

./scripts/config --enable CONFIG_CMDLINE_BOOL
./scripts/config --set-str CONFIG_CMDLINE "root=PARTUUID=8b056c80-db81-4203-aa99-275d27575293 rw console=tty1 console=ttyS0,115200n8 net.ifnames=0 biosdevname=0 fbcon=scrollback:1024k"

make LLVM=1 olddefconfig > /dev/null

echo "[*] Compiling Kernel (This may take a minute or two)..."
make LLVM=1 -j$(nproc)

cp arch/x86/boot/bzImage $OUT_DIR/BOOTX64.EFI
echo "[+] Kernel built successfully at $OUT_DIR/BOOTX64.EFI"