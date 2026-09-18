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
                const next_tab = (self.cursor_col + 8) & ~7;
                self.cursor_col = if (next_tab < COLS) next_tab else COLS - 1;
            },
            else => {
                const flatten_pos = self.cursor_row * COLS + self.cursor_col;
                self.buffer[flatten_pos] = .{ .char = char, .attr = self.color };
                self.cursor_col += 1;
            },
        }
    }
};
