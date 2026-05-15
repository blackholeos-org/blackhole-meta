.PHONY: all userspace kernel image run clean submodules tools repo flash deploy-repo

all: submodules tools userspace kernel image repo

submodules:
	@echo "[*] Checking Git Submodules..."
	@git submodule update --init --recursive || true

userspace:
	@bash scripts/01_build_userspace.sh

kernel: userspace
	@bash scripts/02_build_kernel.sh

image: kernel
	@bash scripts/03_build_image.sh

tools:
	@echo "[*] Using Python for bh-builder, no compilation required."

repo: tools
	@echo "[*] Building Local Blackhole Repositories..."
	@rm -rf out/repo/*.db out/repo/*.db.sig
	@for pkg in packages/*/*/*.bh; do \
		if [ -f "$$pkg" ]; then \
			REPO=$$(echo "$$pkg" | cut -d'/' -f2); \
			python3 src/bh-builder/bh_builder.py add "$$REPO" "$$pkg" || exit 1; \
		fi \
	done
	@echo "[*] Signing all repository databases..."
	@for db in out/repo/*.db; do \
		if [ -f "$$db" ]; then \
			REPO_NAME=$$(basename $$db .db); \
			python3 src/bh-builder/bh_builder.py sign "$$REPO_NAME" || exit 1; \
		fi \
	done
	@echo "[+] Multi-PPA generation complete."
	@echo "[*] To host it, run: python3 -m http.server 8000 -d out/repo"

run:
	@echo "[*] Booting Blackhole OS in QEMU..."
	qemu-system-x86_64 \
		-cpu host \
		-M q35 -enable-kvm -m 1024 \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
		-drive file=out/blackhole-uefi.img,format=raw \
		-nographic

flash:
	@if [ -z "$(DEV)" ]; then \
		echo "ERROR: You must specify a target USB device! (e.g., make flash DEV=/dev/sdb)"; \
		exit 1; \
	fi
	@echo "[!] WARNING: This will DESTROY ALL DATA on $(DEV)!"
	@read -p "Are you absolutely sure? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "[*] Flashing Blackhole OS to $(DEV)..."; \
		sudo dd if=out/blackhole-uefi.img of=$(DEV) bs=4M status=progress oflag=sync; \
		echo "[+] Flashing complete. The drive is now bootable on physical bare-metal hardware."; \
	else \
		echo "[*] Aborted."; \
	fi

deploy-repo:
	@if [ -z "$(SERVER)" ]; then \
		echo "ERROR: Specify SERVER=user@host:/path/to/webroot"; \
		exit 1; \
	fi
	@echo "[*] Rsyncing out/repo to $(SERVER)..."
	@rsync -avz --delete out/repo/ $(SERVER)/
	@echo "[+] Repository deployed to production successfully!"

clean:
	@echo "[*] Cleaning build artifacts..."
	rm -rf out/*
	rm -rf src/linux-*
	rm -rf src/toybox-*
	rm -rf src/busybox-*