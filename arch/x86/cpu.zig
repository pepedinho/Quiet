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

/// Cycle counter. Wrap the read in disable/enable IRQ at the call site
/// and take the min over reps: TSC is invariant on KVM/real CPUs.
pub fn rdtsc() u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | @as(u64, lo);
}
