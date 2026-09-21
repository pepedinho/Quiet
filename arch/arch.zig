//! Architectural abstraction layer.
//!
//! The interface between the kernel and CPU dependant code : the kernel
//! interacts only with this module :
//!     - [`boot`] : boot headers + asm entry point for initializing FPU/SSE
//!     then call main(magic, info) as multiboot required it.
//!     - [`mb2`] : read the boot information delivered by the bootloader (tags, mmap, cmdline).
//!     - [`pio`] : port io interface provide inb/outb.
//!
//! Only x86 implementation exists for now.
//! To add an arch: add `arch/<cpu>` and wire up the re-exports.
//! Kernel code stays unchanged.
//!
//! Shared invariant: everythings is freestanding (no libc, no allocator).
//! Objects from [`mb2`] are view over bootloader provided memory: valid only
//! while its mapping is alive. copy them before paging.

const mod = @import("x86/x86.zig");

pub const boot = mod.boot;
pub const mb2 = mod.mb2;
pub const pio = mod.pio;
pub const pic = mod.pic;
pub const gdt = mod.gdt;
pub const idt = mod.idt;
