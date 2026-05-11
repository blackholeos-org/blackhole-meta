#!/bin/bash
source configs/build.env
set -e

echo "[*] Compiling Userspace..."

rm -rf $OUT_DIR/rootfs $OUT_DIR/kernel_headers
mkdir -p $OUT_DIR/rootfs/{bin,dev,proc,sys,mnt}

if [ ! -d "$KERNEL_SRC" ]; then
    echo "    -> Downloading Kernel source (for headers)..."
    wget -q --show-progress "$KERNEL_URL" -O /tmp/kernel.tar.xz
    tar -xf /tmp/kernel.tar.xz -C $SRC_DIR
    rm /tmp/kernel.tar.xz
fi

echo "    -> Exporting Kernel Headers..."
cd $KERNEL_SRC
make headers_install ARCH=x86_64 INSTALL_HDR_PATH=$OUT_DIR/kernel_headers > /dev/null

if [ ! -d "$TOYBOX_SRC" ]; then
    echo "    -> Downloading Toybox v${TOYBOX_VER}..."
    wget -q --show-progress "$TOYBOX_URL" -O /tmp/toybox.tar.gz
    tar -xzf /tmp/toybox.tar.gz -C $SRC_DIR
    rm /tmp/toybox.tar.gz
    
    echo "    -> Configuring Toybox..."
    cd $TOYBOX_SRC
    make defconfig > /dev/null
    
    sed -i 's/^# CONFIG_SH is not set/CONFIG_SH=y/' .config
    sed -i 's/^# CONFIG_ROUTE is not set/CONFIG_ROUTE=y/' .config
    sed -i 's/^# CONFIG_IP is not set/CONFIG_IP=y/' .config
    sed -i 's/^# CONFIG_DHCP is not set/CONFIG_DHCP=y/' .config
    sed -i 's/^# CONFIG_TR is not set/CONFIG_TR=y/' .config
    sed -i 's/^# CONFIG_AWK is not set/CONFIG_AWK=y/' .config
    sed -i 's/^# CONFIG_PING is not set/CONFIG_PING=y/' .config
    sed -i 's/^# CONFIG_WGET is not set/CONFIG_WGET=y/' .config
    sed -i 's/^# CONFIG_VI is not set/CONFIG_VI=y/' .config
    
    echo "    -> Compiling Toybox statically..."
    CC=musl-gcc CFLAGS="-I$OUT_DIR/kernel_headers/include" LDFLAGS="-static" make -j$(nproc) > /dev/null
fi
cp $TOYBOX_SRC/toybox $OUT_DIR/rootfs/bin/

echo "    -> Compiling Early Boot (bh-initramfs)..."
cd $SRC_DIR/bh-initramfs
musl-gcc -static init.c -o $OUT_DIR/rootfs/init -I$OUT_DIR/kernel_headers/include

echo "    -> Compiling Event Horizon Init System..."
cd $SRC_DIR/bh-horizon
make clean > /dev/null
make CFLAGS="-Wall -Iinclude -O3 -I$OUT_DIR/kernel_headers/include" > /dev/null
cp horizon $OUT_DIR/horizon

echo "    -> Compiling Blackhole Package Manager (bhpkg)..."
cd $SRC_DIR/bhpkg
if [ ! -d "sysroot/lib" ]; then
    echo "       [*] Bootstrapping bhpkg sysroot (This will take a few minutes)..."
    python3 build_sysroot.py
fi
make > /dev/null

cd $OUT_DIR/rootfs
find . | cpio -o -H newc | gzip > $OUT_DIR/rootfs.cpio.gz
echo "[+] Initramfs built at $OUT_DIR/rootfs.cpio.gz"