
ZIG := zig
CACHE_DIR := .zig-cache
TARGET_DIR := zig-out
ISOS := quiet-limine.iso quiet-grub.iso
ISO_DIR := iso-grub iso-limine

all: run

build:
	$(ZIG) build

clean: clean-iso
	rm $(TARGET_DIR) $(CACHE_DIR) -rf

clean-iso:
	rm $(ISOS) $(ISO_DIR) -rf

run: build
	@bootloader=$$( \
				if command -v gum >/dev/null 2>&1;then \
					gum choose "limine" "grub"; \
				else \
					printf "Bootloader [limine/grub]: "; \
					read bootloader; \
					printf "%s\n" "$$bootloader"; \
				fi \
	); \
	echo "run quiet on $$bootloader"; \
	$(ZIG) build run-$$bootloader

run-limine: build
	$(ZIG) build run-limine

run-grub: build
	$(ZIG) build run-grub

.PHONY: build run clean clean-iso run-limine run-grub

