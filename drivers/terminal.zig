//! Return true if top is at this max pos:
//! example:
//! window_height = 4
//! total_row = 11
//!
//!                 ┌─| _ | _ | _ | _ | _ | _ | 0
//!                 │ | _ | _ | _ | _ | _ | _ | 1
//!                 │ | _ | _ | _ | _ | _ | _ | 2
//!        history ─┤ | _ | _ | _ | _ | _ | _ | 3
//!                 │ | _ | _ | _ | _ | _ | _ | 4
//!                 │ | _ | _ | _ | _ | _ | _ | 5
//!                 └─| _ | _ | _ | _ | _ | _ | 6
//!                 ┌─| _ | _ | _ | _ | _ | _ | 7 <- top
//!                 │ | _ | _ | _ | _ | _ | _ | 8
//! visible window ─┤ | _ | _ | _ | _ | _ | _ | 9
//!                 └─| _ | _ | _ | _ | _ | _ | 10 (max) (current row)
//!
//! in this case `atBottom` return true because
//! top cannot be greater than 7 in with a window of 4 rows.

const std = @import("std");
const vga = @import("vga.zig");

pub const COLS: usize = vga.VGA_WIDTH;
/// Visible rows on the screen.
pub const ROWS: usize = vga.VGA_HEIGHT - 1;
pub const SCROLLBACK: usize = 128;
pub const TOTAL_ROWS: usize = ROWS + SCROLLBACK;

pub const BUFFER_SIZE = COLS * TOTAL_ROWS;

pub const default_color: vga.Color = .{ .fg = .light_gray, .bg = .black };

pub const TerminalState = enum {
    normal,
    navigation,
};

pub const Terminal = struct {
    state: TerminalState = .normal,
    buffer: [BUFFER_SIZE]vga.Cell,

    cursor_row: usize = SCROLLBACK,
    cursor_col: usize = 0,

    top: usize,

    color: vga.Color = default_color,

    const Self = @This();

    pub fn nl(self: *Self) void {
        self.cursor_col = 0;
        if (self.cursor_row < TOTAL_ROWS - 1) {
            self.cursor_row += 1;
        } else {
            self.shiftUp();
            //INFO: is the windows has been scrolled up, this line ensure
            //it is returned to is base that the user can see the new line.
            if (!self.atBottom()) self.top = SCROLLBACK;
        }
    }

    /// Shifted by one all internal buffer line
    /// if the buffer is full first line will be deleted to
    /// make room for the new one.
    fn shiftUp(self: *Self) void {
        for (1..TOTAL_ROWS) |r| {
            const src = self.buffer[r * COLS .. (r + 1) * COLS];
            const dst = self.buffer[(r - 1) * COLS .. r * COLS];
            @memcpy(dst, src);
        }

        const last = self.buffer[(TOTAL_ROWS - 1) * COLS .. TOTAL_ROWS * COLS];
        @memset(last, .{ .char = ' ', .attr = self.color });
    }

    /// Return true if top is at it max pos
    pub fn atBottom(self: *Self) bool {
        return self.top == TOTAL_ROWS - ROWS;
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
                if (self.cursor_col == COLS) {
                    self.nl();
                }
            },
        }
    }

    pub fn flush(self: *Self) void {
        var line_idx: usize = self.top;
        while (line_idx < self.top + ROWS) : (line_idx += 1) {
            const pos = line_idx * COLS;
            const line = self.buffer[pos .. pos + COLS];
            for (line, 0..) |cell, i| {
                vga.printCharAt(cell.char, cell.attr, i, line_idx - self.top);
            }
        }
        if (self.atBottom()) {
            vga.placeCuror(self.cursor_row - self.top, self.cursor_col);
        }
    }

    pub fn scrollDown(self: *Self) void {
        self.top = @min(self.top + 1, TOTAL_ROWS - ROWS);
    }

    pub fn scrollUp(self: *Self) void {
        const top_min = 0;
        self.top = @max(self.top - 1, top_min);
    }
};

var terminal: Terminal = undefined;

/// Init VGA driver and [`Terminal`] structure.
pub fn init() void {
    vga.init();
    terminal = .{
        .buffer = [_]vga.Cell{.{ .char = ' ', .attr = default_color }} ** BUFFER_SIZE,
        .cursor_col = 0,
        .top = TOTAL_ROWS - ROWS,
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
    terminal.flush();
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
}
