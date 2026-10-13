const Keyboard = @This();

const std = @import("std");
const win32 = @import("win32").everything;
const xkb = @import("xkbcommon").c;

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

    pub const count = @typeInfo(Key).@"enum".field_names.len;

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
    const down = self.current.isSet(@backingInt(key));
    const prev_down = self.previous.isSet(@backingInt(key));

    return if (down) if (prev_down) .repeat else .press else if (prev_down) .release else .up;
}

pub fn isDown(self: Keyboard, key: Key) bool {
    const down = self.current.isSet(@backingInt(key));
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
    self.current.set(@backingInt(key));
}

pub fn release(self: *Keyboard, key: Key) void {
    self.current.unset(@backingInt(key));
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
        const key: Key = @fromBackingInt(@intCast(i));

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

    const key: win32.VIRTUAL_KEY = @fromBackingInt(@intCast(@as(u16, @truncate(wParam))));

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

pub fn fromXkb(symbol: xkb.xkb_keysym_t) ?Key {
    return switch (symbol) {
        0 => null,
        0x0041, 0x0061 => .a, // A, a
        0x0042, 0x0062 => .b, // B, b
        0x0043, 0x0063 => .c, // C, c
        0x0044, 0x0064 => .d, // D, d
        0x0045, 0x0065 => .e, // E, e
        0x0046, 0x0066 => .f, // F, f
        0x0047, 0x0067 => .g, // G, g
        0x0048, 0x0068 => .h, // H, h
        0x0049, 0x0069 => .i, // I, i
        0x004A, 0x006A => .j, // J, j
        0x004B, 0x006B => .k, // K, k
        0x004C, 0x006C => .l, // L, l
        0x004D, 0x006D => .m, // M, m
        0x004E, 0x006E => .n, // N, n
        0x004F, 0x006F => .o, // O, o
        0x0050, 0x0070 => .p, // P, p
        0x0051, 0x0071 => .q, // Q, q
        0x0052, 0x0072 => .r, // R, r
        0x0053, 0x0073 => .s, // S, s
        0x0054, 0x0074 => .t, // T, t
        0x0055, 0x0075 => .u, // U, u
        0x0056, 0x0076 => .v, // V, v
        0x0057, 0x0077 => .w, // W, w
        0x0058, 0x0078 => .x, // X, x
        0x0059, 0x0079 => .y, // Y, y
        0x005A, 0x007A => .z, // Z, z

        0x0030 => .@"0",
        0x0031 => .@"1",
        0x0032 => .@"2",
        0x0033 => .@"3",
        0x0034 => .@"4",
        0x0035 => .@"5",
        0x0036 => .@"6",
        0x0037 => .@"7",
        0x0038 => .@"8",
        0x0039 => .@"9",

        0xFFBE => .f1, // F1
        0xFFBF => .f2, // F2
        0xFFC0 => .f3, // F3
        0xFFC1 => .f4, // F4
        0xFFC2 => .f5, // F5
        0xFFC3 => .f6, // F6
        0xFFC4 => .f7, // F7
        0xFFC5 => .f8, // F8
        0xFFC6 => .f9, // F9
        0xFFC7 => .f10, // F10
        0xFFC8 => .f11, // F11
        0xFFC9 => .f12, // F12

        0xFFE1 => .left_shift, // Shift_L
        0xFFE2 => .right_shift, // Shift_R
        0xFFE3 => .left_control, // Control_L
        0xFFE4 => .right_control, // Control_R
        0xFFE9 => .left_alt, // Alt_L
        0xFFEA => .right_alt, // Alt_R
        0xFFEB => .left_super, // Super_L
        0xFFEC => .right_super, // Super_R

        0xFF1B => .escape, // Escape
        0xFF0D => .enter, // Return
        0xFF09 => .tab, // Tab
        0xFF08 => .backspace, // BackSpace
        0x0020 => .space, // space

        0xFF63 => .insert, // Insert
        0xFFFF => .delete, // Delete
        0xFF50 => .home, // Home
        0xFF57 => .end, // End
        0xFF55 => .page_up, // Page_Up
        0xFF56 => .page_down, // Page_Down

        0xFF52 => .up, // Up
        0xFF54 => .down, // Down
        0xFF51 => .left, // Left
        0xFF53 => .right, // Right

        0x002D => .minus, // minus
        0x003D => .equal, // equal
        0x005B => .left_bracket, // bracketleft
        0x005D => .right_bracket, // bracketright
        0x003B => .semicolon, // semicolon
        0x0027 => .apostrophe, // apostrophe
        0x002C => .comma, // comma
        0x002E => .period, // period
        0x002F => .slash, // slash
        0x005C => .backslash, // backslash
        0x0060 => .grave, // grave

        0xFFB0 => .keypad_0, // KP_0
        0xFFB1 => .keypad_1, // KP_1
        0xFFB2 => .keypad_2, // KP_2
        0xFFB3 => .keypad_3, // KP_3
        0xFFB4 => .keypad_4, // KP_4
        0xFFB5 => .keypad_5, // KP_5
        0xFFB6 => .keypad_6, // KP_6
        0xFFB7 => .keypad_7, // KP_7
        0xFFB8 => .keypad_8, // KP_8
        0xFFB9 => .keypad_9, // KP_9
        0xFFAB => .keypad_add, // KP_Add
        0xFFAD => .keypad_subtract, // KP_Subtract
        0xFFAA => .keypad_multiply, // KP_Multiply
        0xFFAF => .keypad_divide, // KP_Divide
        0xFF8D => .keypad_enter, // KP_Enter
        0xFFAE => .keypad_decimal, // KP_Decimal

        0xFFE5 => .caps_lock, // Caps_Lock
        0xFF7F => .num_lock, // Num_Lock
        0xFF14 => .scroll_lock, // Scroll_Lock

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
