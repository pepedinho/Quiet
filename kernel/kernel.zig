const std = @import("std");
const arch = @import("arch");
const drivers = @import("drivers");
const b_opt = @import("b_opt");

comptime {
    _ = arch.boot;
}

pub export fn main(magic: u32, mb_info: *arch.mb2.BootInfo) void {
    _ = mb_info;

    if (magic != arch.mb2.BOOTLOADER_MAGIC) {
        @panic("incorrect magic");
    }

    drivers.vga.init();
    drivers.vga.print("Quiet v{s}\n", .{b_opt.version});

    while (true) {}
}
