//! Global Descriptor Table (GDT)
//! see: https://wiki.osdev.org/Global_Descriptor_Table

const std = @import("std");

pub const KERNEL_CODE_SEGMENT: u16 = 0x08;
pub const KERNEL_DATA_SEGMENT: u16 = 0x10;

const GDT_ENTRIES = 7;

const GdtDescriptor = packed struct {
    size: u16,
    offset: u32,
};

const Access = packed struct {
    accessed: u1 = 0, // bit 0
    read_write: u1, // bit 1    code: readable / data: writable
    dc: u1 = 0, // bit 2    code: conforming / data: direction
    executable: u1, // bit 3    1 = code
    system: u1 = 1, // bit 4    S: 1 = code/data, 0 = system
    privilege: u2, // but 5-6  ring
    present: u1 = 1, // bit 7
};

const Flags = packed struct(u4) {
    avl: u1 = 0, // bit 0
    l: u1 = 0, // bit 1    long mode (0)
    d: u1 = 1, // bit 2    D/B 32-bit (1)
    g: u1 = 1, // bit 3    granularity 4KiB (1)
};

const SegmentDescriptor = packed struct(u64) {
    limit_low: u16, // limit[15:0]  -> bits 0..15
    base_low: u16, // base[15:0]   -> bits 16..31
    base_mid: u8, // base[23:16]  -> bits 32..39
    access: Access, //              -> bits 40..47
    limit_high: u4, // limit[19:16] -> bits 48..51
    flags: Flags, //              -> bits 52..55
    base_high: u8, // base[31:24]  -> bits 56..63

    const nil: SegmentDescriptor = @bitCast(@as(u64, 0));

    fn make(base: u32, limit: u20, access: Access, flags: Flags) SegmentDescriptor {
        return .{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .base_mid = @truncate(base >> 16),
            .access = access,
            .limit_high = @truncate(limit >> 16),
            .flags = flags,
            .base_high = @truncate(base >> 24),
        };
    }
};

const gdt_entries = gdt_entries: {
    var tbl: [GDT_ENTRIES]SegmentDescriptor = undefined;
    // 0x00 ~ Null descriptor.
    tbl[0] = .nil;
    // 0x08 ~ Kernel code (ring 0).
    tbl[1] = .make(0, 0xFFFFF, .{ .read_write = 1, .executable = 1, .privilege = 0 }, .{});
    // 0x10 ~ Kernel data (ring 0).
    tbl[2] = .make(0, 0xFFFFF, .{ .read_write = 1, .executable = 0, .privilege = 0 }, .{});
    // 0x18 ~ Kernel stack (ring 0).
    tbl[3] = .make(0, 0xFFFFF, .{ .read_write = 1, .executable = 0, .privilege = 0, .dc = 1 }, .{});

    // 0x20 ~ User code (ring 3).
    tbl[4] = .make(0, 0xFFFFF, .{ .read_write = 1, .executable = 1, .privilege = 3 }, .{});
    // 0x28 ~ User data (ring 3).
    tbl[5] = .make(0, 0xFFFFF, .{ .read_write = 1, .executable = 0, .privilege = 3 }, .{});
    // 0x30 ~ User stack (ring 3).
    tbl[6] = .make(0, 0xFFFFF, .{ .read_write = 1, .executable = 0, .privilege = 3, .dc = 1 }, .{});
    break :gdt_entries tbl;
};

pub fn init() void {
    const gdtr: GdtDescriptor = .{
        .size = @sizeOf(@TypeOf(gdt_entries)) - 1,
        .offset = @intFromPtr(&gdt_entries),
    };

    asm volatile (
        \\lgdt (%[ptr])
        \\ljmp $0x08, $1f
        \\1:
        \\movw $0x10, %%ax
        \\movw %%ax, %%ds
        \\movw %%ax, %%es
        \\movw %%ax, %%fs
        \\movw %%ax, %%gs
        \\movw %%ax, %%ss
        :
        : [ptr] "r" (&gdtr),
        : .{ .ax = true });
}
