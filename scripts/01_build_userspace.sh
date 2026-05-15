#!/bin/bash
source configs/build.env
set -e

echo "[*] Compiling Userspace..."

rm -rf $OUT_DIR/rootfs $OUT_DIR/kernel_headers
mkdir -p $OUT_DIR/rootfs/{bin,dev,proc,sys,mnt,etc/ssl/certs}

if [ ! -d "$KERNEL_SRC" ]; then
    echo "    -> Downloading Kernel source (for headers)..."
    wget -q --show-progress "$KERNEL_URL" -O /tmp/kernel.tar.xz
    tar -xf /tmp/kernel.tar.xz -C $SRC_DIR
    rm /tmp/kernel.tar.xz
fi

echo "    -> Exporting Kernel Headers..."
cd $KERNEL_SRC
make headers_install ARCH=x86_64 INSTALL_HDR_PATH=$OUT_DIR/kernel_headers > /dev/null

echo "    -> Fetching ca-certificates (Mozilla root certs)..."
wget -q "https://curl.se/ca/cacert.pem" -O $OUT_DIR/rootfs/etc/ssl/certs/ca-certificates.crt

if [ ! -d "$BUSYBOX_SRC" ]; then
    echo "    -> Downloading Busybox v${BUSYBOX_VER}..."
    wget -q --show-progress "$BUSYBOX_URL" -O /tmp/busybox.tar.bz2
    tar -xjf /tmp/busybox.tar.bz2 -C $SRC_DIR
    rm /tmp/busybox.tar.bz2

    echo "    -> Configuring Busybox..."
    cd $BUSYBOX_SRC
    make defconfig > /dev/null
    
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
    
    sed -i 's/^# CONFIG_MDEV is not set/CONFIG_MDEV=y/' .config
    sed -i 's/^# CONFIG_FEATURE_MDEV_CONF is not set/CONFIG_FEATURE_MDEV_CONF=y/' .config
    sed -i 's/^# CONFIG_FEATURE_MDEV_EXEC is not set/CONFIG_FEATURE_MDEV_EXEC=y/' .config

    sed -i 's/^# CONFIG_SYSLOGD is not set/CONFIG_SYSLOGD=y/' .config
    sed -i 's/^# CONFIG_FEATURE_SYSLOGD_READ_BUFFER_SIZE/CONFIG_FEATURE_SYSLOGD_READ_BUFFER_SIZE=256/' .config
    sed -i 's/^# CONFIG_KLOGD is not set/CONFIG_KLOGD=y/' .config

    sed -i 's/^# CONFIG_ADDUSER is not set/CONFIG_ADDUSER=y/' .config
    sed -i 's/^# CONFIG_ADDGROUP is not set/CONFIG_ADDGROUP=y/' .config
    sed -i 's/^# CONFIG_DELUSER is not set/CONFIG_DELUSER=y/' .config
    sed -i 's/^# CONFIG_DELGROUP is not set/CONFIG_DELGROUP=y/' .config
    sed -i 's/^# CONFIG_PASSWD is not set/CONFIG_PASSWD=y/' .config
    sed -i 's/^# CONFIG_SU is not set/CONFIG_SU=y/' .config
    
    yes "" | make oldconfig > /dev/null
    
    echo "    -> Compiling Busybox statically..."
    CC=musl-gcc EXTRA_CFLAGS="-Wno-uninitialized -Wno-discarded-qualifiers -Wno-unused-but-set-variable -Wno-dangling-pointer" LDFLAGS="-static" make -j$(nproc) > /dev/null
fi

cp $BUSYBOX_SRC/busybox $OUT_DIR/rootfs/bin/
ln -sf busybox $OUT_DIR/rootfs/bin/sh

echo "    -> Compiling Early Boot (bh-initramfs)..."
cd $SRC_DIR/bh-initramfs
musl-gcc -O3 -flto -fstack-protector-strong -D_FORTIFY_SOURCE=2 -static init.c -o $OUT_DIR/rootfs/init -I$OUT_DIR/kernel_headers/include

echo "    -> Compiling Event Horizon Init System..."
cd $SRC_DIR/bh-horizon
make clean > /dev/null
make CFLAGS="-Wall -Iinclude -O3 -flto -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -I$OUT_DIR/kernel_headers/include" > /dev/null
cp horizon $OUT_DIR/horizon

echo "    -> Compiling Blackhole Package Manager (bhpkg)..."
cd $SRC_DIR/bhpkg
if [ ! -d "sysroot/lib" ]; then
    echo "       [*] Bootstrapping bhpkg sysroot (This will take a few minutes)..."
    python3 build_sysroot.py
fi
make > /dev/null

echo "    -> Compiling Cron Daemon (bh-crond)..."
cd $SRC_DIR/bh-crond
make clean > /dev/null
make > /dev/null
cp bh-crond $OUT_DIR/bh-crond

cd $OUT_DIR/rootfs
find . | cpio -o -H newc | gzip > $OUT_DIR/rootfs.cpio.gz
echo "[+] Initramfs built at $OUT_DIR/rootfs.cpio.gz"