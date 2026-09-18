const std = @import("std");
const pio = @import("arch").pio;

pub const VGA_WIDTH = 80;
pub const VGA_HEIGHT = 25;
pub const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;
pub const VGA_BUFFER: [*]volatile Cell = @ptrFromInt(0xb8000);

var term_row: usize = 0;
var term_col: usize = 0;
var term_color = Color.init(.light_gray, .black);
var term_buffer: [*]volatile Cell = VGA_BUFFER;

pub const Color = packed struct(u8) {
    fg: ColorType,
    bg: ColorType,

    pub fn init(fg: ColorType, bg: ColorType) Color {
        return .{ .fg = fg, .bg = bg };
    }

    /// Take a char and return a VGA formated Cell
    pub fn getCell(self: Color, char: u8) Cell {
        return .{ .attr = self, .char = char };
    }
};

pub const Cell = extern struct {
    char: u8,
    attr: Color,

    // Converting a [`Cell`] into a formated VGA u16
    pub fn getVga(self: Cell) u16 {
        return @as(u16, @as(u8, @bitCast(self.attr))) << 8 | self.char;
    }
};

const ColorType = enum(u4) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    brown = 6,
    light_gray = 7,
    dark_gray = 8,
    light_blue = 9,
    light_green = 10,
    light_cyan = 11,
    light_red = 12,
    light_magenta = 13,
    light_brown = 14,
    white = 15,
};

pub fn init() void {
    clear();
    enableCursor(14, 15);
    syncCursor();
}

/// Clear VGA buffer with empty char and d_color attributes.
pub fn clear() void {
    @memset(term_buffer[0..VGA_SIZE], .{ .char = ' ', .attr = term_color });
}

pub fn enableCursor(start: u8, end: u8) void {
    pio.outb(0x3D4, 0x0A);
    pio.outb(0x3D5, (pio.inb(0x3D5) & 0xC0) | start);
    pio.outb(0x3D4, 0x0B);
    pio.outb(0x3D5, (pio.inb(0x3D5) & 0xE0) | end);
}

pub fn disableCursor() void {
    pio.outb(0x3D4, 0x0A);
    pio.outb(0x3D5, 0x20);
}

pub fn placeCuror(row: usize, col: usize) void {
    const pos = row * VGA_WIDTH + col;
    pio.outb(0x3D4, 0x0F);
    pio.outb(0x3D5, @as(u8, pos & 0xFF));
    pio.outb(0x3D4, 0x0E);
    pio.outb(0x3D5, @as(u8, (pos >> 8) & 0xFF));
}

pub fn syncCursor() void {
    const pos: u16 = @intCast(term_row * VGA_WIDTH + term_col);
    pio.outb(0x3D4, 0x0F);
    pio.outb(0x3D5, @truncate(pos));
    pio.outb(0x3D4, 0x0E);
    pio.outb(0x3D5, @truncate(pos >> 8));
}

/// Change internal VGA driver `term_color`.
/// default:
///     fg: light_gray
///     bg: black
pub fn setColor(fg: ColorType, bg: ColorType) void {
    term_color = .{ .bg = bg, .fg = fg };
}

/// Create a new Cell with provided attribute and put it in the VGA internal buffer.
pub fn printCharAt(char: u8, color: Color, x: usize, y: usize) void {
    const idx = y * VGA_WIDTH + x;
    term_buffer[idx] = .{ .char = char, .attr = color };
}

pub fn printChar(char: u8) void {
    switch (char) {
        '\n' => {
            term_col = 0;
            term_row += 1;
        },
        else => {
            printCharAt(char, term_color, term_col, term_row);
            term_col += 1;
            if (term_col == VGA_WIDTH) {
                term_col = 0;
                term_row += 1;
            }
        },
    }
    syncCursor();
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
    return .{
        .buffer = buffer,
        .end = 0,
        .vtable = &.{
            .drain = drain,
        },
    };
}

pub fn printString(str: []const u8) void {
    for (str) |char| {
        printChar(char);
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
}
