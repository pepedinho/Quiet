//! CPU Control: halt and reboot. Reboot use 8042 reset pulse
//! (mechanism may change: triple fault, ACPI reset register, ...).

const pio = @import("pio.zig");

pub fn hlt() noreturn {
    while (true) asm volatile ("cli; hlt");
}

/// Reset the CPU via 8042 keyboard controller reset pulse.
/// Waits for the status input-buffer bit to drain first, else the
/// 0xFE command is dropped. Halts if the reset never takes.
/// see: https://wiki.osdev.org/Reboot
pub fn reboot() noreturn {
    var good: u8 = 0x02;
    while (good & 0x02 != 0) good = pio.inb(0x64);
    pio.outb(0x64, 0xFE);
    hlt();
}
