const std = @import("std");

const MAX_PARAMS = 8;

pub const Sgr = struct {
    reset: bool = false,
    bold: bool = false,
    fg: ?u8 = null,
    bg: ?u8 = null,
};

pub const Event = union(enum) {
    char: u8,
    sgr: Sgr,
    cursor_home,
    cursor_position: struct { row: u8, col: u8 },
    cursor_up: u8,
    cursor_down: u8,
    cursor_left: u8,
    cursor_right: u8,
    clear_after_cursor,
    clear_until_cursor,
    clear,
};

const State = enum { ground, escape, csi };

pub const Parser = struct {
    state: State = .ground,
    params: [8]u8 = undefined,
    param_count: u8 = 0,
    cur_param: u8 = 0,

    pub fn feed(self: *Parser, byte: u8) ?Event {
        return switch (self.state) {
            .ground => self.feedGround(byte),
            .escape => self.feedEscape(byte),
            .csi => self.feedCsi(byte),
        };
    }

    fn feedGround(self: *Parser, byte: u8) ?Event {
        switch (byte) {
            '\x1b' => {
                self.state = .escape;
                return null;
            },
            else => return .{ .char = byte },
        }
    }

    fn feedEscape(self: *Parser, byte: u8) ?Event {
        var state: State = .ground;
        switch (byte) {
            '[' => {
                state = .csi;
                self.params = [_]u8{0} ** MAX_PARAMS;
                self.param_count = 1;
                self.cur_param = 0;
            },
            else => {},
        }

        self.state = state;
        return null;
    }

    fn feedCsi(self: *Parser, byte: u8) ?Event {
        switch (byte) {
            '0'...'9' => {
                const n = byte - '0';
                self.params[self.cur_param] = self.params[self.cur_param] *| 10 +| n;
            },
            'J' => {
                var event: ?Event = null;
                switch (self.params[0]) {
                    0 => event = .clear_after_cursor,
                    1 => event = .clear_until_cursor,
                    2 => event = .clear,
                    else => {},
                }
                self.state = .ground;
                return event;
            },
            'H' => {
                const y = if (self.params[0] == 0) 1 else self.params[0];
                const x = if (self.params[1] == 0) 1 else self.params[1];
                self.state = .ground;
                return .{ .cursor_position = .{ .row = y, .col = x } };
            },
            ';' => {
                self.cur_param = (self.cur_param + 1) % MAX_PARAMS;
                self.param_count = self.cur_param + 1;
            },
            'A' => {
                self.state = .ground;
                return .{ .cursor_up = self.moveParam() };
            },
            'B' => {
                self.state = .ground;
                return .{ .cursor_down = self.moveParam() };
            },
            'C' => {
                self.state = .ground;
                return .{ .cursor_right = self.moveParam() };
            },
            'D' => {
                self.state = .ground;
                return .{ .cursor_left = self.moveParam() };
            },
            'm' => {
                const sgr = self.buildSgr();
                self.state = .ground;
                return .{ .sgr = sgr };
            },
            else => self.state = .ground,
        }

        return null;
    }

    fn moveParam(self: *const Parser) u8 {
        return if (self.params[0] == 0) 1 else self.params[0];
    }

    fn buildSgr(self: *const Parser) Sgr {
        var sgr: Sgr = .{};
        for (self.params[0..self.param_count]) |p| {
            switch (p) {
                0 => sgr.reset = true,
                1 => sgr.bold = true,
                30...37 => sgr.fg = p - 30,
                40...47 => sgr.bg = p - 40,
                90...97 => sgr.fg = p - 90 + 8,
                100...107 => sgr.bg = p - 100 + 8,
                else => {},
            }
        }
        return sgr;
    }
};

const testing = std.testing;

fn run(seq: []const u8) ?Event {
    var p: Parser = .{};
    var last: ?Event = null;
    for (seq) |c| last = p.feed(c);
    return last;
}

test "raw text" {
    const event = run("a z") orelse unreachable;

    std.debug.assert(event == .char);
    std.debug.assert(event.char == 'z');
}

test "lonely esc" {
    const event = run("\x1b");

    std.debug.assert(event == null);
}

test "reset" {
    const event = run("\x1b[m") orelse unreachable;

    std.debug.assert(event == .sgr);
    std.debug.assert(event.sgr.reset == true);
}

test "simple fg" {
    const event = run("\x1b[31m") orelse unreachable;

    std.debug.assert(event == .sgr);
    std.debug.assert(event.sgr.fg == 1);
}

test "multi params" {
    const event = run("\x1b[31;44;1m") orelse unreachable;

    std.debug.assert(event == .sgr);
    std.debug.assert(event.sgr.fg == 1);
    std.debug.assert(event.sgr.bg == 4);
    std.debug.assert(event.sgr.bold == true);
}

test "empty segment" {
    const event = run("\x1b[;31m") orelse unreachable;

    std.debug.assert(event == .sgr);
    std.debug.assert(event.sgr.fg == 1);
    std.debug.assert(event.sgr.reset == true);
}

test "bright" {
    var event = run("\x1b[97m") orelse unreachable;

    std.debug.assert(event == .sgr);
    std.debug.assert(event.sgr.fg == 15);

    event = run("\x1b[107m") orelse unreachable;

    std.debug.assert(event == .sgr);
    std.debug.assert(event.sgr.bg == 15);
}

test "moves" {
    const up = run("\x1b[2A") orelse unreachable;
    const down = run("\x1b[B") orelse unreachable;
    const right = run("\x1b[0C") orelse unreachable;
    const left = run("\x1b[5D") orelse unreachable;

    std.debug.assert(up == .cursor_up);
    std.debug.assert(down == .cursor_down);
    std.debug.assert(right == .cursor_right);
    std.debug.assert(left == .cursor_left);

    std.debug.assert(up.cursor_up == 2);
    std.debug.assert(down.cursor_down == 1);
    std.debug.assert(right.cursor_right == 1);
    std.debug.assert(left.cursor_left == 5);
}

test "position" {
    var event = run("\x1b[H") orelse unreachable;

    std.debug.assert(event == .cursor_position);
    std.debug.assert(event.cursor_position.col == 1);
    std.debug.assert(event.cursor_position.row == 1);

    event = run("\x1b[5;10H") orelse unreachable;
    std.debug.assert(event == .cursor_position);
    std.debug.assert(event.cursor_position.col == 10);
    std.debug.assert(event.cursor_position.row == 5);
}

test "erase" {
    const after = run("\x1b[J") orelse unreachable;
    const until = run("\x1b[1J") orelse unreachable;
    const clear = run("\x1b[2J") orelse unreachable;

    std.debug.assert(after == .clear_after_cursor);
    std.debug.assert(until == .clear_until_cursor);
    std.debug.assert(clear == .clear);
}

test "saturation" {
    const event = run("\x1b[999A") orelse unreachable;

    std.debug.assert(event == .cursor_up);
    std.debug.assert(event.cursor_up == 255);
}

test "text after move" {
    var p = Parser{};

    _ = p.feed(0x1b);
    _ = p.feed('[');
    _ = p.feed('2');
    const up = p.feed('A') orelse unreachable;
    std.debug.assert(up == .cursor_up);
    std.debug.assert(up.cursor_up == 2);

    const event = p.feed('x') orelse unreachable;
    std.debug.assert(event == .char);
    std.debug.assert(event.char == 'x');
}

test "unknown seq" {
    var p = Parser{};

    _ = p.feed(0x1b);
    _ = p.feed('[');
    _ = p.feed('z');

    const event = p.feed('k') orelse unreachable;
    std.debug.assert(event == .char);
    std.debug.assert(event.char == 'k');
}
