.PHONY: all userspace kernel image run clean submodules

all: submodules userspace kernel image

submodules:
	@echo "[*] Checking Git Submodules..."
	@git submodule update --init --recursive || true

userspace:
	@bash scripts/01_build_userspace.sh

kernel: userspace
	@bash scripts/02_build_kernel.sh

image: kernel
	@bash scripts/03_build_image.sh

run:
	@echo "[*] Booting Blackhole OS in QEMU..."
	qemu-system-x86_64 \
		-M q35 -enable-kvm -m 1024 \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
		-drive file=out/blackhole-uefi.img,format=raw \
		-nographic

clean:
	@echo "[*] Cleaning build artifacts..."
	rm -rf out/*
	rm -rf src/linux-*
	rm -rf src/toybox-*