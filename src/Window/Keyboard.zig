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
    try self.formatState(w, .press);
    try self.formatState(w, .repeat);
    try self.formatState(w, .release);
}

pub fn formatState(self: Keyboard, w: *std.Io.Writer, comptime state: Key.State) std.Io.Writer.Error!void {
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

    if (any_found) try w.writeAll("\n");
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
    const Ks = xkb.Keysym;

    return switch (symbol) {
        Ks.A, Ks.a => .a,
        Ks.B, Ks.b => .b,
        Ks.C, Ks.c => .c,
        Ks.D, Ks.d => .d,
        Ks.E, Ks.e => .e,
        Ks.F, Ks.f => .f,
        Ks.G, Ks.g => .g,
        Ks.H, Ks.h => .h,
        Ks.I, Ks.i => .i,
        Ks.J, Ks.j => .j,
        Ks.K, Ks.k => .k,
        Ks.L, Ks.l => .l,
        Ks.M, Ks.m => .m,
        Ks.N, Ks.n => .n,
        Ks.O, Ks.o => .o,
        Ks.P, Ks.p => .p,
        Ks.Q, Ks.q => .q,
        Ks.R, Ks.r => .r,
        Ks.S, Ks.s => .s,
        Ks.T, Ks.t => .t,
        Ks.U, Ks.u => .u,
        Ks.V, Ks.v => .v,
        Ks.W, Ks.w => .w,
        Ks.X, Ks.x => .x,
        Ks.Y, Ks.y => .y,
        Ks.Z, Ks.z => .z,

        Ks.@"0" => .@"0",
        Ks.@"1" => .@"1",
        Ks.@"2" => .@"2",
        Ks.@"3" => .@"3",
        Ks.@"4" => .@"4",
        Ks.@"5" => .@"5",
        Ks.@"6" => .@"6",
        Ks.@"7" => .@"7",
        Ks.@"8" => .@"8",
        Ks.@"9" => .@"9",

        Ks.F1 => .f1,
        Ks.F2 => .f2,
        Ks.F3 => .f3,
        Ks.F4 => .f4,
        Ks.F5 => .f5,
        Ks.F6 => .f6,
        Ks.F7 => .f7,
        Ks.F8 => .f8,
        Ks.F9 => .f9,
        Ks.F10 => .f10,
        Ks.F11 => .f11,
        Ks.F12 => .f12,

        Ks.Shift_L => .left_shift,
        Ks.Shift_R => .right_shift,
        Ks.Control_L => .left_control,
        Ks.Control_R => .right_control,
        Ks.Alt_L => .left_alt,
        Ks.Alt_R => .right_alt,
        Ks.Super_L => .left_super,
        Ks.Super_R => .right_super,

        Ks.Escape => .escape,
        Ks.Return => .enter,
        Ks.Tab => .tab,
        Ks.BackSpace => .backspace,
        Ks.space => .space,

        Ks.Insert => .insert,
        Ks.Delete => .delete,
        Ks.Home => .home,
        Ks.End => .end,
        Ks.Page_Up => .page_up,
        Ks.Page_Down => .page_down,

        Ks.Up => .up,
        Ks.Down => .down,
        Ks.Left => .left,
        Ks.Right => .right,

        Ks.minus => .minus,
        Ks.equal => .equal,
        Ks.bracketleft => .left_bracket,
        Ks.bracketright => .right_bracket,
        Ks.semicolon => .semicolon,
        Ks.apostrophe => .apostrophe,
        Ks.comma => .comma,
        Ks.period => .period,
        Ks.slash => .slash,
        Ks.backslash => .backslash,
        Ks.grave => .grave,

        Ks.KP_0 => .keypad_0,
        Ks.KP_1 => .keypad_1,
        Ks.KP_2 => .keypad_2,
        Ks.KP_3 => .keypad_3,
        Ks.KP_4 => .keypad_4,
        Ks.KP_5 => .keypad_5,
        Ks.KP_6 => .keypad_6,
        Ks.KP_7 => .keypad_7,
        Ks.KP_8 => .keypad_8,
        Ks.KP_9 => .keypad_9,
        Ks.KP_Add => .keypad_add,
        Ks.KP_Subtract => .keypad_subtract,
        Ks.KP_Multiply => .keypad_multiply,
        Ks.KP_Divide => .keypad_divide,
        Ks.KP_Enter => .keypad_enter,
        Ks.KP_Decimal => .keypad_decimal,

        Ks.Caps_Lock => .caps_lock,
        Ks.Num_Lock => .num_lock,
        Ks.Scroll_Lock => .scroll_lock,

        else => null,
    };
}
