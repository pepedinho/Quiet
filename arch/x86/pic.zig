//! 8259 Programmable Interrupt Controller (PIC)
//! see: https://wiki.osdev.org/8259_PIC

const std = @import("std");
const pio = @import("pio.zig");

/// IO base address for master PIC
const PIC1_CMD = 0x20;
/// IO base address for slave PIC
const PIC2_CMD = 0xA0;
const PIC1_DATA = PIC1_CMD + 1;
const PIC2_DATA = PIC2_CMD + 1;

/// Indicate that ICW4 will be present.
const ICW1_ICW4 = 0x01;
/// Single (cascade) mode.
const ICW1_SINGLE = 0x02;
/// Call address  interval 4 (8).
const ICW1_INTERVAL4 = 0x04;
/// Level triggered (edge) mode.
const ICW1_LEVEL = 0x08;
/// Initialization required !
const ICW1_INIT = 0x10;

/// 8086/88 (MCS-80/85) mode.
const ICW4_8086 = 0x01;
/// Auto (normal) EOI.
const ICW4_AUTO = 0x02;
/// Buffered mode slave.
const ICW4_BUF_SLAVE = 0x08;
/// Buffered mode master.
const ICW4_BUF_MASTER = 0x0C;
/// Special fully nested (not).
const ICW4_SFNM = 0x10;

const CASCADE_IRQ = 2;

pub const PIC1_OFFSET = 0x20;
pub const PIC2_OFFSET = 0x28;

const PIC_EOI = 0x20;

// see: https://wiki.osdev.org/X86_Interrupts#Standard_ISA_IRQs
pub const Irq = enum(u8) {
    timer = 0,
    keyboard = 1,
    cascade = 2,
    com2 = 3,
    com1 = 4,
    lpt2 = 5,
    floppy = 6,
    lpt1 = 7,
    cmos = 8, // real time clock
    mouse = 12,
    fpu = 13,
    primary_ata = 14,
    secondary_ata = 15,
};

const outb = pio.outb;
const inb = pio.inb;
const ioWait = pio.ioWait;

/// Reinitialize the PIC controllers, giving them specified vector offsets
/// rather than 8h and 70h, as configured by default
pub fn init() void {
    outb(PIC1_CMD, ICW1_INIT | ICW1_ICW4);
    ioWait();
    outb(PIC2_CMD, ICW1_INIT | ICW1_ICW4);
    ioWait();
    outb(PIC1_DATA, PIC1_OFFSET);
    ioWait();
    outb(PIC2_DATA, PIC2_OFFSET);
    ioWait();
    outb(PIC1_DATA, 1 << CASCADE_IRQ);
    ioWait();
    outb(PIC2_DATA, CASCADE_IRQ);
    ioWait();

    outb(PIC1_DATA, ICW4_8086);
    ioWait();
    outb(PIC2_DATA, ICW4_8086);
    ioWait();

    outb(PIC1_DATA, 0);
    outb(PIC2_DATA, 0);
}

pub fn sendEoi(irq: Irq) void {
    if (@intFromEnum(irq) >= 8) {
        outb(PIC2_CMD, PIC_EOI);
    }
    outb(PIC1_CMD, PIC_EOI);
}

pub fn irqSetMask(irq: Irq) void {
    if (@intFromEnum(irq) < 8) {
        const value = inb(PIC1_DATA) | @as(u8, 1) << @truncate(@intFromEnum(irq));
        outb(PIC1_DATA, value);
    } else {
        const value = inb(PIC2_DATA) | @as(u8, 1) << @truncate(@intFromEnum(irq) - 8);
        outb(PIC2_DATA, value);
    }
}

pub fn irqClearMask(irq: Irq) void {
    if (@intFromEnum(irq) < 8) {
        const value = inb(PIC1_DATA) & ~(@as(u8, 1) << @truncate(@intFromEnum(irq)));
        outb(PIC1_DATA, value);
    } else {
        const value = inb(PIC2_DATA) & ~(@as(u8, 1) << @truncate(@intFromEnum(irq) - 9));
        outb(PIC2_DATA, value);
    }
}
