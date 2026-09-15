const std = @import("std");

//see: https://www.gnu.org/software/grub/manual/multiboot2/multiboot.html#Header-tags

/// Info request tag
pub const TInfoRequest = extern struct {
    type: u16 = 1,
    flags: u16 = 0,
    size: u32 = @sizeOf(TInfoRequest),
    mbi_tag_types: [3]u32 = .{ 1, 6, 8 }, // cmdline, mmap, framebuffer
};

/// Console tag
pub const Tconsole = extern struct {
    type: u16 = 4,
    flags: u16 = 1,
    size: u32 = @sizeOf(Tconsole),
    console_flags: u32 = (1 << 1),
    _pad: u32 = 0,
};

// End tag
const Tend = extern struct {
    type: u16 = 0,
    flags: u16 = 0,
    size: u32 = 8,
};

//see: https://www.gnu.org/software/grub/manual/multiboot2/multiboot.html
/// Multiboot 2 header
pub const MB2Header = extern struct {
    /// Magic number identifiting the header.
    magic: u32 = 0xE85250D6,
    ///The field `architecture` specifies the Central Proccesing Unit Instruction Set Architecture. Since [`magic`]
    ///isn't a palindrome it already specifies the andianness ISAs differing only endienness recieve the same ID.
    ///'0' means 32-bit(protected) mode of i386. '4' means 32-bit MIPS.
    architecture: u32 = 0,
    ///specifies the Length of Multiboot2 header in bytes including magic fields.
    header_length: u32 = @sizeOf(MB2Header),
    /// is a 32-bit unsigned value which, when added to the other magic fields
    /// (i.e 'magic' 'architecture' and 'header_length'), must have a 32-bit unsigned sum of zero.
    checksum: u32 = 0,
    t_info_request: TInfoRequest = .{},
    _pad: u32 = 0,
    t_console: Tconsole = .{},
    end: Tend = .{},
};

fn initHeader() MB2Header {
    var h: MB2Header = .{};
    h.checksum = 0 -% (h.magic +% h.architecture +% h.header_length);
    return h;
}

export var mb2_header: MB2Header align(8) linksection(".multiboot2") = initHeader();
pub const STACK_SIZE = 4 * 4096;
pub export var STACK: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

const _fpu_init =
    \\
    \\mov %%cr0, %%eax
    \\and $0xFFFFFFFB, %%eax
    \\or  $0x00000002, %%eax
    \\mov %%eax, %%cr0
    \\fninit
    \\
;

const _sse_init =
    \\
    \\pushl %%eax
    \\pushl %%ebx
    \\mov $1, %%eax
    \\cpuid
    \\popl %%ebx
    \\test $0x02000000, %%edx
    \\jz .Lno_sse
    \\
    \\mov %%cr4, %%eax
    \\or $0x00000600, %%eax
    \\mov %%eax, %%cr4
    \\.Lno_sse:
    \\popl %%eax
    \\
;

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\xor %%ebp, %%ebp
        \\movl $STACK + 16384, %%esp
        \\pushl $0
        \\popf
        \\pushl %%ebx
        \\pushl %%eax
    ++
        _fpu_init ++
        _sse_init ++
        \\call main
        \\cli
        \\.Lhalt:
        \\hlt
        \\jmp .Lhalt
    );
}
