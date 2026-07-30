const Keyboard = @This();

const std = @import("std");
const win32 = @import("win32").everything;

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
    num_0,
    num_1,
    num_2,
    num_3,
    num_4,
    num_5,
    num_6,
    num_7,
    num_8,
    num_9,

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
        none = 0,
        press = 1,
        release = 2,
        repeat = 3,

        /// Prefer using `Keyboard.isDown` when a `Keyboard` instance is available,
        /// as it provides the current state directly.
        pub fn isDown(self: State) bool {
            return switch (self) {
                .press, .repeat => true,
                .none, .release => false,
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

    return if (down) if (prev_down) .repeat else .press else if (prev_down) .release else .none;
}

pub fn isDown(self: Keyboard, key: Key) bool {
    const down = self.current.isSet(@intFromEnum(key));
    return down;
}

pub fn isUp(self: Keyboard, key: Key) bool {
    return !self.isDown(key);
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
        .@"0" => .num_0,
        .@"1" => .num_1,
        .@"2" => .num_2,
        .@"3" => .num_3,
        .@"4" => .num_4,
        .@"5" => .num_5,
        .@"6" => .num_6,
        .@"7" => .num_7,
        .@"8" => .num_8,
        .@"9" => .num_9,

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
