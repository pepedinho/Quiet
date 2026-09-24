//! Kernel crash diagnostics: panic handler, CPU exception handler and
//! frame-pointer stack trace dumps over the serial line.
//!
//! # Panic flow
//! Every `@panic` / Zig safety check (index out of bounds, overflow, …)
//! routes to [`panicHandler`] through the root declaration in `kernel.zig`:
//!     pub const panic = std.debug.FullPanic(panicHandler);
//! (`std/builtin.zig` looks up `root.panic`; `FullPanic` turns every safety
//! panic into a formatted message + a call to our handler). The handler:
//!   1. masks interrupts (`cli`),
//!   2. prints the message on COM1,
//!   3. walks the EBP chain and prints raw return addresses,
//!   4. halts the CPU forever (`hlt` loop) — the kernel never returns.
//!
//! # Exception flow
//! [`exceptionHandler`] is registered for DE(0), UD(6), DF(8), GP(13),
//! PF(14), AC(17) in `kernel.zig` `main`. Error-code-less vectors get a fake
//! 0 pushed by `generateStub`, so the `InterruptFrame` layout is uniform.
//! We dump vector name / err / eip / cs / eflags, then the stack trace
//! STARTING from the interrupted frame's saved `ebp` (preserved by `pusha`
//! in the isr stub before dispatch). `eip` is printed as frame #0: it is the
//! exact faulting instruction.
//!
//! # Why a hand-rolled frame-pointer walk (no runtime symbols)
//! Resolving addresses at runtime needs parsing our own ELF/DWARF in memory
//! (see osdev.org "Stack Trace") — a heavy project. Instead we dump raw
//! return addresses and resolve them OFFLINE against the built ELF:
//!     addr2line -e zig-out/bin/quiet.k -f -i 0x…
//! This works because multiboot loads the kernel at its p_vaddr and the
//! Debug build keeps DWARF info (verified: frames map to shell.run/main).
//!
//! # Stack layout (x86 SysV ABI, frame pointers ON)
//! `build.zig` sets `omit_frame_pointer = false` on every module, so each
//! function prologue is `push ebp; mov ebp, esp` and each frame stores:
//!     [ebp + 0]  saved ebp (caller's frame pointer) → chain link
//!     [ebp + 4]  return address (into the caller)
//! The stack grows DOWN, so walking from the innermost frame outward
//! strictly increases the address: `next <= ebp` detects a corrupted chain.
//!
//! # Skip-until semantics ([`printStack`])
//! During a panic the innermost frames belong to std panic machinery
//! (`FullPanic`/`panicExtra`). `std.builtin.panic.call(msg, ret_addr)` gives
//! `ret_addr` = the return address in USER code that triggered the panic.
//! We walk the chain and ignore frames until we find the std frame whose
//! return address == `ret_addr` (the frame that returns into user code),
//! print that address as frame #0 (the crash site), then keep walking.
//! If `ret_addr` is null or never found: print the whole chain (std noise
//! in the head — acceptable fallback).
//!
//! # Caveats / invariants
//! - Frame pointers MUST be enabled, else the walk falls apart immediately;
//!   heavy inlining (ReleaseFast) collapses frames and degrades the trace.
//! - Without paging every linear address maps 1:1, so reading garbage frame
//!   pointers can never fault — the walker is crash-safe by construction.
//! - `@tagName` needs a NAMED vector; only the 6 registered vectors (all
//!   named) can reach [`exceptionHandler`].
//! - #DF (double fault) is best-effort: without a TSS/IST the stack may be
//!   clobbered before the handler runs — the trace may be garbage.

const std = @import("std");
const drivers = @import("drivers");
const arch = @import("arch");

var panicked = false;

/// Walk the EBP chain from `start` and print one `#d 0x…` line per frame
/// on COM1. If `skip_until` is set, ignore frames until their return
/// address matches, then print from there (see module doc "Skip-until").
fn printStack(start: usize, skip_until: ?usize) void {
    var ebp: usize = start;

    if (skip_until) |addr| {
        var guard: usize = 0;
        while (guard < 32) : (guard += 1) {
            if (load(ebp + 4) == addr) break;
            const next = load(ebp);
            if (next <= ebp or next == 0) return;
            ebp = next;
        }
        if (load(ebp + 4) != addr) return;
    }

    drivers.serial.print("stack trace:\n", .{});
    var frame: usize = 0;
    while (ebp != 0 and frame < 32) : (frame += 1) {
        const ra = load(ebp + 4);
        drivers.serial.print("#{d} 0x{x}\n", .{ frame, ra });
        const next = load(ebp);
        if (next <= ebp) break;
        ebp = next;
    }
}

/// Read a usize at an arbitrary linear address (align(1): no safety check).
fn load(addr: usize) usize {
    return @as(*align(1) const usize, @ptrFromInt(addr)).*;
}

/// Panic entry point from `std.builtin.panic.all`. Masks IRQs, print the
/// message, dump the stack trace, then halts. `panicked` guards recursion.
pub fn panicHandler(msg: []const u8, ret_addr: ?usize) noreturn {
    arch.idt.disableInterrupts();
    if (panicked) arch.cpu.hlt();
    panicked = true;
    drivers.serial.print("KERNEL PANIC: {s}\n", .{msg});
    printCleanStack(ret_addr);
    arch.cpu.hlt();
}

fn printCleanStack(ret_addr: ?usize) void {
    printStack(@frameAddress(), ret_addr);
}

/// CPU exception handler (registered for DE/UD/DF/GP/PF/AC).
/// Print vector + registers, dump the trace from the interrupted EBP,
/// then halts.
pub fn exceptionHandler(frame: *arch.idt.InterruptFrame) void {
    arch.idt.disableInterrupts();
    if (panicked) arch.cpu.hlt();
    panicked = true;
    const int_name = @tagName(@as(arch.idt.Interrupt, @enumFromInt(frame.int_no)));
    drivers.serial.print("EXCEPTION: {s} err=0x{x} eip=0x{x} cs={x} eflags={x}\n", .{ int_name, frame.err, frame.eip, frame.cs, frame.eflags });
    traceFromEbp(frame.ebp, frame.eip);
    arch.cpu.hlt();
}

/// Trace for exception: `eip` as frame #0 (faulting instruction), then the
/// caller chain from the interrupted context's saved EBP.
fn traceFromEbp(ebp: usize, eip: usize) void {
    drivers.serial.print("stack trace:\n", .{});
    drivers.serial.print("#0 0x{x}\n", .{eip});
    var cur: usize = ebp;
    var frame: usize = 1;
    while (cur != 0 and frame < 32) : (frame += 1) {
        const ra = load(cur + 4);
        drivers.serial.print("#{d} 0x{x}\n", .{ frame, ra });
        const next = load(cur);
        if (next <= cur) break;
        cur = next;
    }
}
