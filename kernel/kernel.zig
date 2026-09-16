const std = @import("std");
const arch = @import("arch");
const drivers = @import("drivers");

comptime {
    _ = arch.boot;
}

pub export fn main(magic: u32, mb_info: *arch.mb2.BootInfo) void {
    _ = mb_info;

    drivers.vga.init();
    drivers.vga.print("Quiet v0.2.0\n", .{});
    if (magic != arch.mb2.BOOTLOADER_MAGIC) {
        @panic("incorrect magic");
    }
    while (true) {}
}
