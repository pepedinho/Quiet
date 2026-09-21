const std = @import("std");
const arch = @import("arch");
const drivers = @import("drivers");
const b_opt = @import("b_opt");

comptime {
    _ = arch.boot;
}

pub export fn main(magic: u32, mb_info: *arch.mb2.BootInfo) void {
    _ = mb_info;
    drivers.serial.init();

    arch.gdt.init();
    drivers.serial.print("[STEP] GDT loaded.\n", .{});
    arch.idt.init();
    drivers.serial.print("[STEP] IDT init.\n", .{});
    arch.pic.init();
    drivers.serial.print("[STEP] PIC remapped.\n", .{});
    arch.idt.enableInterrupts();

    if (magic != arch.mb2.BOOTLOADER_MAGIC) {
        @panic("incorrect magic");
    }

    drivers.serial.print("[STEP] Magic check done.\n", .{});

    drivers.keyboard.init();
    drivers.serial.print("[STEP] keyboard init.\n", .{});
    drivers.terminal.init();
    drivers.terminal.print("bonjour\n", .{});
    drivers.serial.print("[STEP] Vga init done.\n", .{});
    drivers.terminal.print("Quiet v{s}\n", .{b_opt.version});

    while (true) {
        while (drivers.keyboard.readKey()) |key| {
            switch (key) {
                .char => |c| drivers.terminal.print("{c}", .{c}),
                .func => |n| drivers.terminal.print("F{d}", .{n}),
            }
        }
        asm volatile ("hlt");
    }
}
