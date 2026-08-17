const Keyboard = @This();

const std = @import("std");
const win32 = @import("win32").everything;
const xkb = @import("xkbcommon");

previous: BitSet = .empty,
current: BitSet = .empty,

pub const BitSet = std.bit_set.IntegerBitSet(Key.count);

pub const Key = enum(u8) {
    // Letters
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    // Numbers
    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    // Modifiers
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_super,
    right_super,

    // Navigation
    escape,
    enter,
    tab,
    backspace,
    space,

    insert,
    delete,
    home,
    end,
    page_up,
    page_down,

    up,
    down,
    left,
    right,

    // Punctuation
    minus,
    equal,
    left_bracket,
    right_bracket,
    semicolon,
    apostrophe,
    comma,
    period,
    slash,
    backslash,
    grave,

    // Keypad
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,
    keypad_add,
    keypad_subtract,
    keypad_multiply,
    keypad_divide,
    keypad_enter,
    keypad_decimal,

    // Lock keys
    caps_lock,
    num_lock,
    scroll_lock,

    pub const count = @typeInfo(Key).@"enum".fields.len;

    pub const State = enum(u2) {
        up = 0,
        press = 1,
        release = 2,
        repeat = 3,

        /// Prefer using `Keyboard.isDown` when a `Keyboard` instance is available,
        /// as it provides the current state directly.
        pub fn isDown(self: State) bool {
            return switch (self) {
                .press, .repeat => true,
                .up, .release => false,
            };
        }

        /// Prefer using `Keyboard.isUp` when a `Keyboard` instance is available,
        /// as it provides the current state directly.
        pub fn isUp(self: State) bool {
            return !self.isDown();
        }
    };
};

pub fn get(self: Keyboard, key: Key) Key.State {
    const down = self.current.isSet(@intFromEnum(key));
    const prev_down = self.previous.isSet(@intFromEnum(key));

    return if (down) if (prev_down) .repeat else .press else if (prev_down) .release else .up;
}

pub fn isDown(self: Keyboard, key: Key) bool {
    const down = self.current.isSet(@intFromEnum(key));
    return down;
}

pub fn isUp(self: Keyboard, key: Key) bool {
    return !self.isDown(key);
}

pub fn anyDown(self: Keyboard) bool {
    return self.current.mask > 0;
}

pub fn anyUp(self: Keyboard) bool {
    return !self.anyDown();
}

pub fn press(self: *Keyboard, key: Key) void {
    self.current.set(@intFromEnum(key));
}

pub fn release(self: *Keyboard, key: Key) void {
    self.current.unset(@intFromEnum(key));
}

pub fn progress(self: *Keyboard) void {
    self.previous = self.current;
}

pub fn format(self: Keyboard, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (try self.formatState(w, .press)) try w.writeByte('\n');
    if (try self.formatState(w, .repeat)) try w.writeByte('\n');
    if (try self.formatState(w, .release)) try w.writeByte('\n');
}

pub fn formatState(self: Keyboard, w: *std.Io.Writer, comptime state: Key.State) std.Io.Writer.Error!bool {
    var first = true;
    var any_found = false;

    for (0..Key.count) |i| {
        const key: Key = @enumFromInt(i);

        if (self.get(key) != state) continue;

        if (!any_found) {
            try w.print("{t}: ", .{state});
            any_found = true;
        }

        if (!first) try w.writeAll(", ");

        try w.writeAll(@tagName(key));
        first = false;
    }

    return any_found;
}

pub fn fromWin32(wParam: win32.WPARAM, lParam: win32.LPARAM) ?Key {
    const scancode: u32 = (@as(u32, @intCast(lParam)) >> 16) & 0xFF;
    const extended: bool = ((lParam >> 24) & 1) != 0;

    const key: win32.VIRTUAL_KEY = @enumFromInt(@as(u16, @truncate(wParam)));

    return switch (key) {
        // Letters
        .A => .a,
        .B => .b,
        .C => .c,
        .D => .d,
        .E => .e,
        .F => .f,
        .G => .g,
        .H => .h,
        .I => .i,
        .J => .j,
        .K => .k,
        .L => .l,
        .M => .m,
        .N => .n,
        .O => .o,
        .P => .p,
        .Q => .q,
        .R => .r,
        .S => .s,
        .T => .t,
        .U => .u,
        .V => .v,
        .W => .w,
        .X => .x,
        .Y => .y,
        .Z => .z,

        // Numbers
        .@"0" => .@"0",
        .@"1" => .@"1",
        .@"2" => .@"2",
        .@"3" => .@"3",
        .@"4" => .@"4",
        .@"5" => .@"5",
        .@"6" => .@"6",
        .@"7" => .@"7",
        .@"8" => .@"8",
        .@"9" => .@"9",

        // Function keys
        .F1 => .f1,
        .F2 => .f2,
        .F3 => .f3,
        .F4 => .f4,
        .F5 => .f5,
        .F6 => .f6,
        .F7 => .f7,
        .F8 => .f8,
        .F9 => .f9,
        .F10 => .f10,
        .F11 => .f11,
        .F12 => .f12,

        // Modifiers
        .SHIFT => switch (std.enums.fromInt(win32.VIRTUAL_KEY, win32.MapVirtualKeyW(scancode, win32.MAPVK_VSC_TO_VK_EX)) orelse .LSHIFT) {
            .LSHIFT => .left_shift,
            .RSHIFT => .right_shift,
            else => .left_shift, // fallback
        },
        .CONTROL => if (extended) .right_control else .left_control,
        .MENU => if (extended) .right_alt else .left_alt,
        .LWIN => .left_super,
        .RWIN => .right_super,

        // Navigation
        .ESCAPE => .escape,
        .RETURN => .enter,
        .TAB => .tab,
        .BACK => .backspace,
        .SPACE => .space,

        .INSERT => .insert,
        .DELETE => .delete,
        .HOME => .home,
        .END => .end,
        .PRIOR => .page_up,
        .NEXT => .page_down,

        .UP => .up,
        .DOWN => .down,
        .LEFT => .left,
        .RIGHT => .right,

        // Punctuation
        .OEM_MINUS => .minus,
        .OEM_PLUS => .equal,
        .OEM_4 => .left_bracket,
        .OEM_6 => .right_bracket,
        .OEM_1 => .semicolon,
        .OEM_7 => .apostrophe,
        .OEM_COMMA => .comma,
        .OEM_PERIOD => .period,
        .OEM_2 => .slash,
        .OEM_5 => .backslash,
        .OEM_3 => .grave,

        // Keypad
        .NUMPAD0 => .keypad_0,
        .NUMPAD1 => .keypad_1,
        .NUMPAD2 => .keypad_2,
        .NUMPAD3 => .keypad_3,
        .NUMPAD4 => .keypad_4,
        .NUMPAD5 => .keypad_5,
        .NUMPAD6 => .keypad_6,
        .NUMPAD7 => .keypad_7,
        .NUMPAD8 => .keypad_8,
        .NUMPAD9 => .keypad_9,
        .ADD => .keypad_add,
        .SUBTRACT => .keypad_subtract,
        .MULTIPLY => .keypad_multiply,
        .DIVIDE => .keypad_divide,
        .DECIMAL => .keypad_decimal,

        // Lock keys
        .CAPITAL => .caps_lock,
        .NUMLOCK => .num_lock,
        .SCROLL => .scroll_lock,

        else => null,
    };
}

pub fn fromXkb(symbol: xkb.Keysym) ?Key {
    return switch (symbol) {
        .A, .a => .a,
        .B, .b => .b,
        .C, .c => .c,
        .D, .d => .d,
        .E, .e => .e,
        .F, .f => .f,
        .G, .g => .g,
        .H, .h => .h,
        .I, .i => .i,
        .J, .j => .j,
        .K, .k => .k,
        .L, .l => .l,
        .M, .m => .m,
        .N, .n => .n,
        .O, .o => .o,
        .P, .p => .p,
        .Q, .q => .q,
        .R, .r => .r,
        .S, .s => .s,
        .T, .t => .t,
        .U, .u => .u,
        .V, .v => .v,
        .W, .w => .w,
        .X, .x => .x,
        .Y, .y => .y,
        .Z, .z => .z,

        .@"0" => .@"0",
        .@"1" => .@"1",
        .@"2" => .@"2",
        .@"3" => .@"3",
        .@"4" => .@"4",
        .@"5" => .@"5",
        .@"6" => .@"6",
        .@"7" => .@"7",
        .@"8" => .@"8",
        .@"9" => .@"9",

        .F1 => .f1,
        .F2 => .f2,
        .F3 => .f3,
        .F4 => .f4,
        .F5 => .f5,
        .F6 => .f6,
        .F7 => .f7,
        .F8 => .f8,
        .F9 => .f9,
        .F10 => .f10,
        .F11 => .f11,
        .F12 => .f12,

        .Shift_L => .left_shift,
        .Shift_R => .right_shift,
        .Control_L => .left_control,
        .Control_R => .right_control,
        .Alt_L => .left_alt,
        .Alt_R => .right_alt,
        .Super_L => .left_super,
        .Super_R => .right_super,

        .Escape => .escape,
        .Return => .enter,
        .Tab => .tab,
        .BackSpace => .backspace,
        .space => .space,

        .Insert => .insert,
        .Delete => .delete,
        .Home => .home,
        .End => .end,
        .Page_Up => .page_up,
        .Page_Down => .page_down,

        .Up => .up,
        .Down => .down,
        .Left => .left,
        .Right => .right,

        .minus => .minus,
        .equal => .equal,
        .bracketleft => .left_bracket,
        .bracketright => .right_bracket,
        .semicolon => .semicolon,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .period => .period,
        .slash => .slash,
        .backslash => .backslash,
        .grave => .grave,

        .KP_0 => .keypad_0,
        .KP_1 => .keypad_1,
        .KP_2 => .keypad_2,
        .KP_3 => .keypad_3,
        .KP_4 => .keypad_4,
        .KP_5 => .keypad_5,
        .KP_6 => .keypad_6,
        .KP_7 => .keypad_7,
        .KP_8 => .keypad_8,
        .KP_9 => .keypad_9,
        .KP_Add => .keypad_add,
        .KP_Subtract => .keypad_subtract,
        .KP_Multiply => .keypad_multiply,
        .KP_Divide => .keypad_divide,
        .KP_Enter => .keypad_enter,
        .KP_Decimal => .keypad_decimal,

        .Caps_Lock => .caps_lock,
        .Num_Lock => .num_lock,
        .Scroll_Lock => .scroll_lock,

        else => null,
    };
}

pub fn fromCocoa(key_code: u32) ?Key {
    return switch (key_code) {
        // Letters
        0 => .a,
        11 => .b,
        8 => .c,
        2 => .d,
        14 => .e,
        3 => .f,
        5 => .g,
        4 => .h,
        34 => .i,
        38 => .j,
        40 => .k,
        37 => .l,
        46 => .m,
        45 => .n,
        31 => .o,
        35 => .p,
        12 => .q,
        15 => .r,
        1 => .s,
        17 => .t,
        32 => .u,
        9 => .v,
        13 => .w,
        7 => .x,
        16 => .y,
        6 => .z,

        // Numbers
        29 => .@"0",
        18 => .@"1",
        19 => .@"2",
        20 => .@"3",
        21 => .@"4",
        23 => .@"5",
        22 => .@"6",
        26 => .@"7",
        28 => .@"8",
        25 => .@"9",

        // Function keys
        122 => .f1,
        120 => .f2,
        99 => .f3,
        118 => .f4,
        96 => .f5,
        97 => .f6,
        98 => .f7,
        100 => .f8,
        101 => .f9,
        109 => .f10,
        103 => .f11,
        111 => .f12,

        // Modifiers
        56 => .left_shift,
        60 => .right_shift,
        59 => .left_control,
        62 => .right_control,
        58 => .left_alt,
        61 => .right_alt,
        55 => .left_super,
        54 => .right_super,

        // Navigation
        53 => .escape,
        36 => .enter,
        48 => .tab,
        51 => .backspace,
        49 => .space,

        114 => .insert,
        117 => .delete,
        115 => .home,
        119 => .end,
        116 => .page_up,
        121 => .page_down,

        126 => .up,
        125 => .down,
        123 => .left,
        124 => .right,

        // Punctuation
        27 => .minus,
        24 => .equal,
        33 => .left_bracket,
        30 => .right_bracket,
        41 => .semicolon,
        39 => .apostrophe,
        43 => .comma,
        47 => .period,
        44 => .slash,
        42 => .backslash,
        50 => .grave,

        // Keypad
        82 => .keypad_0,
        83 => .keypad_1,
        84 => .keypad_2,
        85 => .keypad_3,
        86 => .keypad_4,
        87 => .keypad_5,
        88 => .keypad_6,
        89 => .keypad_7,
        91 => .keypad_8,
        92 => .keypad_9,
        69 => .keypad_add,
        78 => .keypad_subtract,
        67 => .keypad_multiply,
        75 => .keypad_divide,
        76 => .keypad_enter,
        65 => .keypad_decimal,

        // Lock keys
        57 => .caps_lock,
        71 => .num_lock,
        107 => .scroll_lock,

        else => null,
    };
}
