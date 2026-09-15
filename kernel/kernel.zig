const std = @import("std");
const arch = @import("arch");

comptime {
    _ = arch.boot;
}

pub export fn main(magic: u32, mb_info: *arch.mb2.BootInfo) void {
    _ = mb_info;
    if (magic != arch.mb2.BOOTLOADER_MAGIC) {
        @panic("incorrect magic");
    }
    while (true) {}
}
