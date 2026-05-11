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

make LLVM=1 olddefconfig > /dev/null

echo "[*] Compiling Kernel (This may take a minute or two)..."
make LLVM=1 -j$(nproc)

cp arch/x86/boot/bzImage $OUT_DIR/BOOTX64.EFI
echo "[+] Kernel built successfully at $OUT_DIR/BOOTX64.EFI"