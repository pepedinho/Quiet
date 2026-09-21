const std = @import("std");
const arch = @import("arch");
const pio = arch.pio;
const pic = arch.pic;
const idt = arch.idt;

const KBD_DATA: u16 = 0x60;

const pairs = .{
    .{ 0x02, '1', '!' },  .{ 0x03, '2', '@' }, .{ 0x04, '3', '#' },
    .{ 0x05, '4', '$' },  .{ 0x06, '5', '%' }, .{ 0x07, '6', '^' },
    .{ 0x08, '7', '&' },  .{ 0x09, '8', '*' }, .{ 0x0A, '9', '(' },
    .{ 0x0B, '0', ')' },  .{ 0x0C, '-', '_' }, .{ 0x0D, '=', '+' },
    .{ 0x1A, '[', '{' },  .{ 0x1B, ']', '}' }, .{ 0x27, ';', ':' },
    .{ 0x28, '\'', '"' }, .{ 0x29, '`', '~' }, .{ 0x2B, '\\', '|' },
    .{ 0x33, ',', '<' },  .{ 0x34, '.', '>' }, .{ 0x35, '/', '?' },
};

const rows = .{
    .{ .start = 0x10, .chars = "qwertyuiop" },
    .{ .start = 0x1E, .chars = "asdfghjkl" },
    .{ .start = 0x2C, .chars = "zxcvbnm" },
};

comptime {
    for (pairs) |p| {
        if (base_map[p[0]] != p[1]) @compileError("base_map[p[0]] != p[1]");
        if (shift_map[p[0]] != p[2]) @compileError("base_map[p[0]] != p[2]");
    }
}

const base_map: [0x80]u8 = blk: {
    var m: [0x80]u8 = [_]u8{0} ** 0x80;
    for (rows) |row| {
        for (row.chars, 0..) |c, i| {
            m[row.start + i] = c;
        }
    }
    for (pairs) |p| m[p[0]] = p[1];
    m[0x02 + 0] = '1';
    m[0x0E] = '\x08';
    m[0x1C] = '\n';
    m[0x0F] = '\t';
    m[0x39] = ' ';
    break :blk m;
};

const shift_map: [0x80]u8 = blk: {
    var m = base_map;
    for (&m) |*c| {
        if (std.ascii.isAlphabetic(c.*)) c.* = std.ascii.toUpper(c.*);
    }
    for (pairs) |p| m[p[0]] = p[2];
    break :blk m;
};

const NavKey = enum {
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    insert,
    delete,
};

pub const Key = union(enum) {
    char: u8,
    func: u8,
    nav: NavKey,
};

///FIFO
const RBuffer = struct {
    internal: [256]Key,
    head: u8 = 0,
    tail: u8 = 0,

    const Self = @This();

    pub fn push(self: *Self, key: Key) void {
        const next_head = self.head +% 1;

        if (next_head == self.tail) return;

        self.internal[self.head] = key;
        self.head = next_head;
    }

    pub fn pop(self: *Self) ?Key {
        if (self.tail == self.head) return null;

        const key = self.internal[self.tail];
        self.tail +%= 1;

        return key;
    }
};

var buffer: RBuffer = undefined;
var ext = false;
var shift: bool = false;
var ctrl = false;
var alt = false;
var caps_lock = false;

fn keyboardHandler(frame: *idt.InterruptFrame) void {
    _ = frame;

    const data = pio.inb(KBD_DATA);
    const is_break = data & 0x80 != 0;
    const scancode = data & 0x7F;

    if (data == 0xE0) {
        ext = true;
        pic.sendEoi(.keyboard);
        return;
    }

    if (ext) {
        ext = false;
        if (is_break) {
            pic.sendEoi(.keyboard);
            return;
        }

        switch (scancode) {
            0x48 => buffer.push(.{ .nav = .up }),
            0x50 => buffer.push(.{ .nav = .down }),
            0x4B => buffer.push(.{ .nav = .left }),
            0x4D => buffer.push(.{ .nav = .right }),
            0x47 => buffer.push(.{ .nav = .home }),
            0x4F => buffer.push(.{ .nav = .end }),
            0x49 => buffer.push(.{ .nav = .page_up }),
            0x51 => buffer.push(.{ .nav = .page_down }),
            0x52 => buffer.push(.{ .nav = .insert }),
            0x53 => buffer.push(.{ .nav = .delete }),
            else => {},
        }

        pic.sendEoi(.keyboard);
        return;
    }

    switch (scancode) {
        0x2A, 0x36 => shift = !is_break,
        0x1D => ctrl = !is_break,
        0x38 => alt = !is_break,
        0x3A => caps_lock = if (!is_break) !caps_lock else caps_lock,

        0x0E => if (!is_break) buffer.push(.{ .char = '\x08' }),
        0x1C => if (!is_break) buffer.push(.{ .char = '\n' }),
        0x0F => if (!is_break) buffer.push(.{ .char = '\t' }),
        0x39 => if (!is_break) buffer.push(.{ .char = ' ' }),

        0x3B...0x44 => if (!is_break) buffer.push(.{ .func = @as(u8, scancode - 0x3B + 1) }),
        0x57 => if (!is_break) buffer.push(.{ .func = 11 }),
        0x58 => if (!is_break) buffer.push(.{ .func = 12 }),

        else => if (!is_break) {
            var ch = base_map[scancode];
            if (shift) {
                ch = shift_map[scancode];
            } else if (caps_lock and std.ascii.isAlphabetic(ch)) {
                ch = std.ascii.toUpper(ch);
            }
            if (ch != 0) buffer.push(.{ .char = ch });
        },
    }

    pic.sendEoi(.keyboard);
}

pub fn init() void {
    idt.registerHandler(
        @enumFromInt(pic.PIC1_OFFSET + @intFromEnum(pic.Irq.keyboard)),
        keyboardHandler,
    );
    pic.irqClearMask(.keyboard);
}

pub fn readKey() ?Key {
    return buffer.pop();
}
