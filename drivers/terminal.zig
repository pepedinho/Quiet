//! Terminal driver: instance-based console with scrollback, viewport
//! navigation and a status bar on the last screen row.
//!
//! # Layout
//! Each [`Terminal`] owns a ring of `TOTAL_ROWS` rows made of `SCROLLBACK`
//! history rows plus a window of `ROWS` visible rows. The visible window
//! is picked with `top` in `0..SCROLLBACK`. Below it, the last physical
//! row ([`STATUS_BAR_ROW`]) is reserved for the status bar and is never
//! written by terminal content.
//!
//! Current Terminal implementation  representation
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
//!
//! # Color contract
//! Backgrounds MUST be < 8 (bit 7 = 0) to avoid hardware blinking; the
//! status bar uses `light_gray`. `flush` re-renders rows `0..ROWS-1`
//! only — never the status bar row. Active tab highlight uses `fg`.
//!
//! # Public API
//! terminal: init / activate / switchState / scrollUp / scrollDown /
//! activeTerminal / currentState; Terminal: print / printString / flush.

const std = @import("std");
const vga = @import("vga.zig");
const ansi = @import("ansi.zig");

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
    buffer: [BUFFER_SIZE]vga.Cell,

    cursor_row: usize = SCROLLBACK,
    cursor_col: usize = 0,

    top: usize,

    color: vga.Color = default_color,
    parser: ansi.Parser = .{},

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

    pub fn backspace(self: *Self) void {
        if (self.cursor_col > 0) {
            self.cursor_col -= 1;
        } else if (self.cursor_row > 0) {
            self.cursor_row -= 1;
            self.cursor_col = COLS - 1;
        }
        self.buffer[self.cursor_row * COLS + self.cursor_col] = .{ .char = ' ', .attr = self.color };
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

    /// Terminal translate ansi event in screen action.
    fn handleAnsi(self: *Self, event: ansi.Event) void {
        switch (event) {
            .char => |c| {
                if (c < 0x20) return;
                const flatten_pos = self.cursor_row * COLS + self.cursor_col;
                self.buffer[flatten_pos] = .{ .char = c, .attr = self.color };
                self.cursor_col += 1;
                if (self.cursor_col == COLS) self.nl();
            },
            .sgr => |sgr| self.applySgr(sgr),
            .cursor_home => {
                self.cursor_row = self.top;
                self.cursor_col = 0;
            },
            .cursor_position => |pos| self.setCursorPos(pos.row, pos.col),
            .cursor_up => |n| self.moveCursor(-@as(isize, n), 0),
            .cursor_down => |n| self.moveCursor(@as(isize, n), 0),
            .cursor_left => |n| self.moveCursor(0, -@as(isize, n)),
            .cursor_right => |n| self.moveCursor(0, @as(isize, n)),
            .clear_after_cursor => self.eraseFromCursor(),
            .clear_until_cursor => self.eraseToCursor(),
            .clear => self.eraseDisplay(),
        }
    }

    fn applySgr(self: *Self, sgr: ansi.Sgr) void {
        if (sgr.reset) self.color = default_color;
        if (sgr.fg) |i| {
            const idx: u8 = if (sgr.bold and i < 8) i + 8 else i;
            self.color.fg = @enumFromInt(@as(u4, @intCast(idx)));
        }
        if (sgr.bg) |i| {
            self.color.bg = @enumFromInt(@as(u4, @intCast(@min(i, 7))));
        }
    }

    fn moveCursor(self: *Self, rows: isize, cols: isize) void {
        const nr = @as(isize, @intCast(self.cursor_row)) + rows;
        self.cursor_row = @intCast(std.math.clamp(
            nr,
            @as(isize, @intCast(self.top)),
            @as(isize, @intCast(self.top + ROWS - 1)),
        ));
        const nc = @as(isize, @intCast(self.cursor_col)) + cols;
        self.cursor_col = @intCast(std.math.clamp(nc, @as(isize, 0), @as(isize, @intCast(COLS - 1))));
    }

    fn setCursorPos(self: *Self, row: u8, col: u8) void {
        self.cursor_row = @min(self.top + @as(usize, row) - 1, self.top + ROWS - 1);
        self.cursor_col = @min(@as(usize, col) - 1, COLS - 1);
    }

    fn clearRowFrom(self: *Self, row: usize, col: usize) void {
        const line = self.buffer[row * COLS .. (row + 1) * COLS];
        @memset(line[col..], .{ .char = ' ', .attr = self.color });
    }

    fn eraseDisplay(self: *Self) void {
        for (self.top..self.top + ROWS) |r| self.clearRowFrom(r, 0);
    }

    fn eraseFromCursor(self: *Self) void {
        self.clearRowFrom(self.cursor_row, self.cursor_col);
        for (self.cursor_row + 1..self.top + ROWS) |r| self.clearRowFrom(r, 0);
    }

    fn eraseToCursor(self: *Self) void {
        for (self.top..self.cursor_row) |r| self.clearRowFrom(r, 0);

        const line = self.buffer[self.cursor_row * COLS .. (self.cursor_row + 1) * COLS];
        @memset(line[0..self.cursor_col], .{ .char = ' ', .attr = self.color });
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
            '\x08' => self.backspace(),
            else => if (self.parser.feed(char)) |event| {
                self.handleAnsi(event);
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

const MAX_TERMINAL: usize = 8;
var terminals: [MAX_TERMINAL]Terminal = undefined;
var active_idx: usize = 0;
var g_state: TerminalState = .normal;

/// Init VGA driver and [`Terminal`] structure.
pub fn init() void {
    vga.init();
    terminals = [_]Terminal{.{
        .buffer = [_]vga.Cell{.{ .char = ' ', .attr = default_color }} ** BUFFER_SIZE,
        .cursor_col = 0,
        .top = TOTAL_ROWS - ROWS,
    }} ** MAX_TERMINAL;

    renderStatusBar();
}

///Change active terminal to the provided idx.
///if idx is out of bounds this function
///applied a modulo on the provided value
pub fn activate(idx: usize) void {
    active_idx = idx % MAX_TERMINAL;
    terminals[active_idx].flush();
    switchState(.normal);
}

/// Change the state of terminal driver
pub fn switchState(state: TerminalState) void {
    g_state = state;
    renderStatusBar();
}

pub fn scrollUp() void {
    terminals[active_idx].scrollUp();
}

pub fn scrollDown() void {
    terminals[active_idx].scrollDown();
}

/// Return the idx of the current active terminal.
pub fn activeTerminal() usize {
    return active_idx;
}

/// Return the state of terminal driver.
pub fn currentState() TerminalState {
    return g_state;
}

pub const STATUS_BAR_ROW: usize = vga.VGA_HEIGHT - 1;
const status_bar_color: vga.Color = .{ .fg = .black, .bg = .light_gray };

fn renderStatusBar() void {
    for (0..COLS) |i| {
        vga.printCharAt(' ', status_bar_color, i, STATUS_BAR_ROW);
    }

    const tab_buffer_size: usize = (MAX_TERMINAL * 2) + 2;
    var tabs = [_]u8{' '} ** tab_buffer_size;
    var i: usize = 0;

    for (0..MAX_TERMINAL) |tab| {
        const written = if (tab == active_idx)
            std.fmt.bufPrint(tabs[i .. i + 4], "[{d}] ", .{tab}) catch return
        else
            std.fmt.bufPrint(tabs[i .. i + 2], "{d} ", .{tab}) catch return;
        i += written.len;
    }

    var color: vga.Color = status_bar_color;
    for (tabs, 0..) |char, idx| {
        if (char == '[') {
            color.fg = .light_red;
        }

        vga.printCharAt(char, color, idx, STATUS_BAR_ROW);

        if (char == ']') {
            color.fg = .black;
        }
    }

    const state = @tagName(g_state);
    const start = vga.VGA_WIDTH - state.len;
    for (state, 0..) |char, idx| {
        vga.printCharAt(char, status_bar_color, start + idx, STATUS_BAR_ROW);
    }
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
        terminals[active_idx].printChar(char);
    }
    terminals[active_idx].flush();
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
}
