const std = @import("std");
const arch = @import("arch");
const pio = arch.pio;
const pic = arch.pic;
const idt = arch.idt;

const KBD_DATA: u16 = 0x60;

const rows = .{
    .{ .start = 0x10, .chars = "qwertyuiop" },
    .{ .start = 0x1E, .chars = "asdfghjkl" },
    .{ .start = 0x2C, .chars = "zxcvbnm" },
};

const base_map: [0x80]u8 = blk: {
    var m: [0x80]u8 = [_]u8{0} ** 0x80;
    for (rows) |row| {
        for (row.chars, 0..) |c, i| {
            m[row.start + i] = c;
        }
    }
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
    m[0x02] = '!';
    m[0x03] = '@';
    break :blk m;
};

pub const Key = union(enum) {
    char: u8,
    func: u8,
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
var shift: bool = false;
var ctrl = false;
var alt = false;
var caps_lock = false;

fn keyboardHandler(frame: *idt.InterruptFrame) void {
    _ = frame;

    const data = pio.inb(KBD_DATA);
    const is_break = data & 0x80 != 0;
    const scancode = data & 0x7F;

    switch (scancode) {
        0x2A, 0x36 => shift = !is_break,
        0x1D => ctrl = !is_break,
        0x38 => alt = !is_break,
        0x3A => caps_lock = if (!is_break) !caps_lock else caps_lock,

        0x0E => if (!is_break) buffer.push(.{ .char = '\x08' }),
        0x1C => if (!is_break) buffer.push(.{ .char = '\n' }),
        0x0F => if (!is_break) buffer.push(.{ .char = '\t' }),
        0x39 => if (!is_break) buffer.push(.{ .char = ' ' }),

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
