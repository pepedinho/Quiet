#!/usr/bin/env bash
# Smoke test: boot the kernel under QEMU and assert expected serial output.
#
# Usage: scripts/smoke.sh [OPTIMIZE] [ISO]
#   OPTIMIZE  value for -Doptimize=...            (default: Debug)
#   ISO       ISO to boot, relative to the CWD    (default: quiet-grub.iso)
#
# Asserts:
#   1. The six "[STEP]" boot markers on the serial line (GDT, IDT, PIC,
#      magic check, keyboard, VGA init).
#   2. "up arrow" after injecting an Up-arrow key via the QEMU monitor,
#      which exercises IRQ1 and the extended (0xE0) scancode path.
#

set -euo pipefail

OPT="${1:-Debug}"
ISO="${2:-quiet-grub.iso}"
LOG="$(mktemp -t quietos-serial.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

if ! command -v qemu-system-i386 >/dev/null 2>&1; then
    echo "error: qemu-system-i386 is required" >&2
    exit 1
fi

zig build iso-grub -Doptimize="$OPT" >/dev/null
if [ ! -f "$ISO" ]; then
    echo "error: $ISO not found (build it with: zig build iso-grub)" >&2
    exit 1
fi

set +e
(
    sleep 4
    echo "sendkey ret"
    sleep 3
    echo "sendkey up"
    sleep 1
    echo "quit"
) | timeout 45 qemu-system-i386 \
    -cdrom "$ISO" \
    -serial "file:$LOG" \
    -monitor stdio \
    -display none \
    -no-reboot -no-shutdown \
    -m 64 >/dev/null 2>&1
set -e

echo "--- serial log ---"
cat "$LOG"
echo "------------------"

# Check boot markers
grep -qF "[STEP] GDT loaded"        "$LOG"
grep -qF "[STEP] IDT init"          "$LOG"
grep -qF "[STEP] PIC remapped"      "$LOG"
grep -qF "[STEP] Magic check done"  "$LOG"
grep -qF "[STEP] keyboard init"     "$LOG"
grep -qF "[STEP] Vga init done"     "$LOG"
grep -qF "up arrow"                 "$LOG"

echo "smoke OK ($OPT, $ISO)"
