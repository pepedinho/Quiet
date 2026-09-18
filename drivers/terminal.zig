const std = @import("std");
const vga = @import("vga.zig");

pub const COLS: usize = vga.VGA_WIDTH;
pub const ROWS: usize = vga.VGA_HEIGHT - 1;

pub const BUFFER_SIZE = COLS * ROWS;

pub const TerminalState = enum {
    normal,
    navigation,
};

pub const Terminal = struct {
    state: TerminalState = .normal,
    buffer: [BUFFER_SIZE]vga.Cell,
    cursor_row: usize,
    cursor_col: usize,

    color: vga.Color = .{ .fg = .dark_gray, .bg = .black },

    const Self = @This();

    pub fn nl(self: *Self) void {
        self.cursor_col = 0;
        if (self.cursor_row < ROWS - 1) {
            self.cursor_row += 1;
        }
    }

    pub fn printChar(self: *Self, char: u8) void {
        switch (char) {
            '\n' => self.nl(),
            '\r' => self.cursor_col = 0,
            '\t' => {
                const next_tab = (self.cursor_col + 8) & ~@as(usize, 7);
                self.cursor_col = if (next_tab < COLS) next_tab else COLS - 1;
            },
            else => {
                const flatten_pos = self.cursor_row * COLS + self.cursor_col;
                self.buffer[flatten_pos] = .{ .char = char, .attr = self.color };
                self.cursor_col += 1;
            },
        }
    }

    pub fn flush(self: *Self) void {
        var line_idx: usize = 0;
        while (line_idx != ROWS) : (line_idx += 1) {
            const pos = line_idx * COLS;
            const line = self.buffer[pos .. pos + COLS];
            for (line) |cell| {
                vga.printChar(cell.char);
            }
            vga.printChar('\n');
        }
    }
};

var terminal: Terminal = undefined;

/// Init VGA driver and [`Terminal`] structure.
pub fn init() void {
    vga.init();
    terminal = .{
        .buffer = [_]vga.Cell{.{ .char = ' ', .attr = terminal.color }} ** BUFFER_SIZE,
        .cursor_col = 0,
        .cursor_row = 0,
    };
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    var consumed: usize = 0;
    const pattern = data[data.len - 1];
    const splat_len = pattern.len * splat;

    if (w.end != 0) {
        printString(w.buffered());
        w.end = 0;
    }

    for (data[0 .. data.len - 1]) |bytes| {
        printString(bytes);
        consumed += bytes.len;
    }

    switch (pattern.len) {
        0 => {},
        else => {
            for (0..splat) |_| {
                printString(pattern);
            }
        },
    }

    consumed += splat_len;
    return consumed;
}

pub fn writer(buffer: []u8) std.Io.Writer {
    return .{ .buffer = buffer, .end = 0, .vtable = &.{
        .drain = drain,
    } };
}

pub fn printString(str: []const u8) void {
    for (str) |char| {
        terminal.printChar(char);
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
    terminal.flush();
}
