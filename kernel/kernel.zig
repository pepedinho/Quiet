const std = @import("std");
const arch = @import("arch");
const drivers = @import("drivers");
const b_opt = @import("b_opt");
const shell = @import("shell.zig");
const debug = @import("debug.zig");

comptime {
    _ = arch.boot;
}

pub export fn main(magic: u32, mb_info: *arch.mb2.BootInfo) void {
    _ = mb_info;
    drivers.serial.init();

    arch.gdt.init();
    drivers.serial.print("[STEP] GDT loaded.\n", .{});
    arch.idt.init();
    arch.idt.registerHandler(.divide_error, debug.exceptionHandler);
    arch.idt.registerHandler(.invalid_opcode, debug.exceptionHandler);
    arch.idt.registerHandler(.double_fault, debug.exceptionHandler);
    arch.idt.registerHandler(.general_protection, debug.exceptionHandler);
    arch.idt.registerHandler(.page_fault, debug.exceptionHandler);
    arch.idt.registerHandler(.alignment_check, debug.exceptionHandler);
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
    drivers.terminal.print("\x1b[31m42\x1b[m\n", .{});
    drivers.serial.print("[STEP] Vga init done.\n", .{});
    drivers.terminal.print("Quiet v{s}\n", .{b_opt.version});

    shell.run();
}

const panic = std.debug.FullPanic(@import("debug.zig").panicHandler);
