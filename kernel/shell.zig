const std = @import("std");
const drivers = @import("drivers");
const terminal = drivers.terminal;
const keyboard = drivers.keyboard;

const Command = struct {
    name: []const u8,
    desc: []const u8,
    handler: *const fn (args: []const u8) void,
};

const commands = [_]Command{
    .{ .name = "help", .desc = "Display all available commande for Quiet", .handler = cHelp },
    .{ .name = "crash", .desc = "Crash manualy for debug pupose", .handler = cCrash },
};

pub fn run() void {
    var line: [terminal.COLS]u8 = undefined;
    var line_len: usize = 0;

    terminal.print("> ", .{});

    while (true) {
        while (drivers.keyboard.readKey()) |key| {
            switch (terminal.currentState()) {
                .normal => switch (key) {
                    .char => |c| switch (c) {
                        '\n' => {
                            terminal.putChar(c);
                            if (line_len > 0) exec(line[0..line_len]) else terminal.print("> ", .{});
                            line_len = 0;
                        },
                        '\x08' => {
                            if (line_len > 0) {
                                terminal.putChar(c);
                                line_len -= 1;
                            }
                        },
                        '\x1b' => terminal.switchState(.navigation),
                        else => {
                            if (line_len < line.len - 1) {
                                line[line_len] = c;
                                terminal.putChar(c);
                                line_len += 1;
                            }
                        },
                    },
                    else => {},
                },
                .navigation => switch (key) {
                    .nav => |n| switch (n) {
                        .left => terminal.previousTab(),
                        .right => terminal.nextTab(),
                        .up => terminal.scrollUp(),
                        .down => terminal.scrollDown(),
                        else => {},
                    },
                    .char => |c| switch (c) {
                        '\x1b', '\n' => terminal.switchState(.normal),
                        else => {},
                    },
                    else => {},
                },
            }
            terminal.flush();
        }
        asm volatile ("hlt");
    }
}

fn exec(line: []const u8) void {
    for (commands) |cmd| {
        if (std.mem.eql(u8, cmd.name, line)) {
            cmd.handler(line);
            terminal.print("> ", .{});
            return;
        }
    }
    terminal.print("No commands named '{s}'\n> ", .{line});
}

fn cHelp(args: []const u8) void {
    _ = args;
    terminal.print("Help:\n", .{});
    for (commands) |cmd| {
        terminal.print("{s:<8}{s}\n", .{ cmd.name, cmd.desc });
    }
    terminal.putChar('\n');
}

fn cCrash(args: []const u8) void {
    _ = args;
    @panic("asked crash");
}
