pub const BOOTLOADER_MAGIC: u32 = 0x36d76289;

/// Boot informations consists of fixed part and a series of tags.
/// Its start is 8-bytes aligned.
pub const BootInfo = extern struct {
    /// Contain total size of boot informations including this field
    /// and terminating tag in bytes.
    total_size: u32,
    /// is always set to zero and must be ignored by OS image
    reserved: u32,
};

pub const TagType = enum(u32) {
    end = 0,
    cmdline = 1,
    mmap = 6,
    framebuffer = 8,
    _,
};

pub const Tag = extern struct {
    type: TagType,
    size: u32,
};

pub const BiosBootDevTag = extern struct {
    base: Tag,
    biosdev: u32,
    partition: u32,
    sub_partition: u32,
};

pub const CmdLineTag = extern struct {
    base: Tag,

    pub fn string(self: *CmdLineTag) [*:0]u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Tag));
    }
};

pub const MMapEntry = extern struct {
    base_addr: u64,
    length: u64,
    type: enum(u32) {
        available = 1,
        reserved = 2,
        acpi_info = 3,
        hibernation_reserved = 4,
        defective_ram = 5,
    },
    reserved: u32,
};

pub const MMapTag = extern struct {
    base: Tag,
    entry_size: u32,
    entry_version: u32,

    pub fn entries(self: *MMapTag) []MMapEntry {
        const raw: [*]MMapEntry = @ptrFromInt(@intFromPtr(self) + @sizeOf(MMapTag));

        if (self.base.size < @sizeOf(MMapTag)) return raw[0..0];
        if (self.entry_size < @sizeOf(MMapEntry)) return raw[0..0];

        const count = (self.base.size - @sizeOf(MMapTag)) / self.entry_size;
        return raw[0..count];
    }
};

pub const BootLoaderNameTag = extern struct {
    base: Tag,

    pub fn string(self: *BootLoaderNameTag) [*:0]u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Tag));
    }
};

pub fn parse(info: *BootInfo, hook: anytype) void {
    const end = @intFromPtr(info) + info.total_size;
    var addr = @intFromPtr(info) + 8;

    while (addr + @sizeOf(Tag) <= end) {
        const tag: *Tag = @ptrFromInt(addr);

        if (tag.size < @sizeOf(Tag) or tag.size > end - addr) break;

        switch (tag.type) {
            .end => break,
            .cmdline => if (@hasDecl(hook, "onCmdLine"))
                hook.onCmdLine(@fieldParentPtr("base", tag)),
            .mmap => if (@hasDecl(hook, "onMMap"))
                hook.onMMap(@fieldParentPtr("base", tag)),
            _ => {},
        }

        addr += (tag.size + 7) & ~@as(usize, 7);
    }
}
