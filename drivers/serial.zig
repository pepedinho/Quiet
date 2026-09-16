//! Serial UART (16550) drivers COM1, polled, no interrupts.
//!
//! Exposes a blocking bytes/string interface at 115200 baud, 8N1.
//!
//! Design: IER=0 and MCR without OUT2 (0x03) so no serial IRQ is ever routed
//! to the PIC; FIFO disabled (FCR 0x00) to stay predictable without IRQs.
//!
//! Invariants:
//!     - call [`init`] once before any print/pullChar.
//!     - every LSR wait can spin forever if the hardware is absent/broken
//!       or if init was skipped: there is NO timeout.
//!     - [`pullChar`] blocks until a byte arrives: it requires a sender.
//!     - only COM1 is used; COM2-4 are declared as standard references.

const std = @import("std");
const pio = @import("arch").pio;

const COM1: u16 = 0x3F8;
const COM2: u16 = 0x2F8;
const COM3: u16 = 0x3E8;
const COM4: u16 = 0x2E8;

pub fn init() void {
    pio.outb(COM1 + 1, 0x00);
    pio.outb(COM1 + 3, 0x80);
    pio.outb(COM1 + 0, 0x01);
    pio.outb(COM1 + 1, 0x00);
    pio.outb(COM1 + 3, 0x03);
    pio.outb(COM1 + 2, 0x00);
    pio.outb(COM1 + 4, 0x03);
}

fn isTransmitEmpty() bool {
    return pio.inb(COM1 + 5) & 0x20 != 0;
}

fn received() bool {
    return pio.inb(COM1 + 5) & 1 != 0;
}

pub fn printChar(char: u8) void {
    while (!isTransmitEmpty()) {}
    pio.outb(COM1, char);
}

pub fn pullChar() u8 {
    while (!received()) {}
    return pio.inb(COM1);
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    var consumed: usize = 0;
    const pattern = data[data.len - 1];
    const splat_len = pattern.len * splat;

    if (w.end != 0) {
        printString(w.buffered());
        w.end = 0;
    }

    for (data[0 .. data.len - 1]) |bytes| {
        printString(bytes);
        consumed += bytes.len;
    }

    switch (pattern.len) {
        0 => {},
        else => {
            for (0..splat) |_| {
                printString(pattern);
            }
        },
    }

    consumed += splat_len;
    return consumed;
}

pub fn writer(buffer: []u8) std.Io.Writer {
    return .{ .buffer = buffer, .end = 0, .vtable = &.{
        .drain = drain,
    } };
}

pub fn printString(str: []const u8) void {
    for (str) |c| printChar(c);
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
}
