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

    arch.pic.init();
    drivers.serial.print("[STEP] PIC remapped.\n", .{});
    arch.gdt.init();
    drivers.serial.print("[STEP] GDT loaded.\n", .{});

    if (magic != arch.mb2.BOOTLOADER_MAGIC) {
        @panic("incorrect magic");
    }

    drivers.serial.print("[STEP] Magic check done.\n", .{});

    drivers.terminal.init();
    drivers.terminal.print("bonjour\n", .{});
    drivers.serial.print("[STEP] Vga init done.\n", .{});
    drivers.terminal.print("Quiet v{s}\n", .{b_opt.version});

    while (true) {}
}
