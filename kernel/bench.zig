const std = @import("std");
const b_opt = @import("b_opt");
const drivers = @import("drivers");
const arch = @import("arch");
const shell = @import("shell.zig");
const vga = drivers.vga;
const terminal = drivers.terminal;

const ITERS: usize = 100;
const REPS: usize = 5;

pub const Workload = struct {
    name: []const u8,
    run: *const fn (iters: usize) void,
};

pub const Suite = struct {
    name: []const u8,
    workloads: []const Workload,
};

pub const Counter = struct {
    name: []const u8,
    value: *const usize,
};

const all_counters = if (b_opt.perf)
    [_]Counter{
        .{ .name = "vga.stores", .value = &vga.Stats.stores },
        .{ .name = "vga.flushes", .value = &vga.Stats.flushes },
    }
else
    [_]Counter{};

fn wChar(iters: usize) void {
    for (0..iters) |_| {
        terminal.putChar('x');
        terminal.flush();
    }
}

fn wLine(iters: usize) void {
    for (0..iters) |_| {
        for (0..terminal.COLS) |_| terminal.putChar('x');
        terminal.flush();
    }
}

fn wFull(iters: usize) void {
    for (0..iters) |_| {
        terminal.clear();
        terminal.flush();
    }
}

fn wPrompt(iters: usize) void {
    for (0..iters) |_| terminal.print("> ", .{});
}

fn wHelp(iters: usize) void {
    for (0..iters) |_| shell.runHelp();
}

const micro_suite = [_]Workload{
    .{ .name = "char", .run = wChar },
    .{ .name = "line", .run = wLine },
    .{ .name = "full", .run = wFull },
};

const scenario_suite = [_]Workload{
    .{ .name = "prompt", .run = wPrompt },
    .{ .name = "help", .run = wHelp },
};

const suites = [_]Suite{
    .{ .name = "terminal", .workloads = &micro_suite },
    .{ .name = "shell", .workloads = &scenario_suite },
};

fn snapshotCounters() [all_counters.len]usize {
    var snap: [all_counters.len]usize = undefined;
    for (all_counters, 0..) |c, i| snap[i] = c.value.*;
    return snap;
}

pub fn runAll() void {
    if (!comptime b_opt.perf) return;

    for (suites) |suite| {
        for (suite.workloads) |wl| {
            const before = snapshotCounters();
            var min_cyc: u64 = std.math.maxInt(u64);
            for (0..REPS) |_| {
                arch.idt.disableInterrupts();
                const t0 = arch.cpu.rdtsc();
                wl.run(ITERS);
                const dt = arch.cpu.rdtsc() - t0;
                arch.idt.enableInterrupts();
                min_cyc = @min(min_cyc, dt);
            }
            const after = snapshotCounters();

            drivers.serial.print("[PERF] {s}.{s} cycles={d}", .{ suite.name, wl.name, min_cyc });
            for (all_counters, 0..) |c, i| {
                drivers.serial.print(" {s}={d}", .{ c.name, after[i] - before[i] });
            }
            drivers.serial.print("\n", .{});
        }
    }
    drivers.serial.print("[PERF] done\n", .{});
}
