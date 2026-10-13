const Window = @This();

const native_os = @import("builtin").target.os.tag;

const std = @import("std");

inner: Inner,

should_close: bool = false,
size: Size,
max_size: ?Window.Size = null,
min_size: ?Window.Size = null,
position: Position,
focused: bool = true,
pointer: Pointer = .{},
keyboard: Keyboard = .{},

pub const Inner = switch (native_os) {
    .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => union(XdgSessionType) {
        wayland: @import("Window/Wayland.zig"),
        x11: @import("Window/Xlib.zig"),
    },
    .windows => @import("Window/Win32.zig"),
    .macos => @import("Window/Cocoa.zig"),
    else => struct {
        const open = @compileError("unsupported platform");
        const close = @compileError("unsupported platform");
        const poll = @compileError("unsupported platform");
        const setTitle = @compileError("unsupported platform");
        const setMaxSize = @compileError("unsupported platform");
        const setMinSize = @compileError("unsupported platform");
        const minimize = @compileError("unsupported platform");
        const maximize = @compileError("unsupported platform");
        const restore = @compileError("unsupported platform");
        const setFullscreen = @compileError("unsupported platform");
        const setPointerVisible = @compileError("unsupported platform");
        const setPointerConstraint = @compileError("unsupported platform");
        const setPointerRelative = @compileError("unsupported platform");
    },
};

const XdgSessionType = enum(u1) {
    wayland,
    x11,

    pub const env = "XDG_SESSION_TYPE";

    pub fn detect(init: std.process.Init.Minimal) ?XdgSessionType {
        var args = init.args.iterate();
        _ = args.skip();

        const session = while (args.next()) |arg| {
            const identifier = "--xdg=";
            if (!std.mem.startsWith(u8, arg, identifier)) continue;
            break arg[identifier.len..];
        } else init.environ.getPosix(env) orelse return null;

        return std.meta.stringToEnum(XdgSessionType, session) orelse null;
    }
};

pub const Size = packed struct(u64) {
    width: u32 = 0,
    height: u32 = 0,

    pub fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }

    pub fn aspect(size: Size) f32 {
        return @as(f32, @floatFromInt(size.width)) / @as(f32, @floatFromInt(size.height));
    }

    /// Returns the size components as a tuple.
    /// Can be coerced into @Vector(2, i32) or [2]i32.
    ///
    /// Example:
    /// ```zig
    /// const x, const y = size.xy();
    /// ```
    pub fn xy(size: Size) struct { u32, u32 } {
        return .{ size.width, size.height };
    }
};

pub const Position = packed struct(i64) {
    x: i32 = 0,
    y: i32 = 0,

    pub fn eql(a: Position, b: Position) bool {
        return a.x == b.x and a.y == b.y;
    }

    /// Returns the position components as a tuple.
    /// Can be coerced into @Vector(2, i32) or [2]i32.
    ///
    /// Example:
    /// ```zig
    /// const x, const y = position.xy();
    /// ```
    pub fn xy(position: Position) struct { i32, i32 } {
        return .{ position.x, position.y };
    }
};

pub const Pointer = struct {
    movement: Movement = .{ .position = .{} },
    buttons: Buttons = .{},
    axis: Axis = .{},

    visible: bool = true,
    constraint: Window.Pointer.Constraint = .none,
    is_relative: bool = false,

    pub const Movement = union(enum) {
        position: struct {
            x: f64 = 0,
            y: f64 = 0,
        },
        relative: struct {
            dx: f64 = 0,
            dy: f64 = 0,
        },
    };

    pub const Buttons = packed struct {
        left: bool = false,
        middle: bool = false,
        right: bool = false,

        forward: bool = false,
        back: bool = false,
        extra1: bool = false,
        extra2: bool = false,
        extra3: bool = false,
    };

    /// Horizontal and vertical scroll
    pub const Axis = struct {
        horizontal: f64 = 0,
        vertical: f64 = 0,
    };

    pub const Constraint = enum {
        none,
        confined,
        locked,
    };
};

pub const Keyboard = @import("Window/Keyboard.zig");

pub const OpenOptions = struct {
    app_id: ?[:0]const u8 = null, // e.g "my_app"
    title: [:0]const u8,
    size: Size,
    position: ?Position = null,
};

pub fn open(window: *Window, init: std.process.Init, options: OpenOptions) !void {
    window.inner = switch (native_os) {
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => blk: {
            const session_type = XdgSessionType.detect(init.minimal) orelse .x11;
            switch (session_type) {
                inline else => |inline_session_type| break :blk @unionInit(Inner, @tagName(inline_session_type), undefined),
            }
        },
        else => undefined,
    };

    window.* = .{
        .inner = window.inner,
        .size = options.size,
        .position = options.position orelse .{ .x = 0, .y = 0 },
    };

    try window.call(.open, if (native_os == .windows) .{ init.gpa, options } else .{options});
}

pub fn close(window: *Window) void {
    window.call(.close, .{}) catch unreachable;
    window.* = undefined;
}

/// Allows optional outputs, such as receiving text input events.
pub const PollOptions = struct {
    /// Optional writer to receive text input events.
    /// Characters are encoded as UTF-8.
    text: ?*std.Io.Writer = null,
};

/// Processes pending window events and updates the window state for the current frame.
/// Should be called once per frame.
pub fn poll(window: *Window, options: PollOptions) !void {
    if (!window.focused) {
        window.pointer.buttons = .{};
        window.keyboard = .{};
    }

    if (window.pointer.movement == .relative) window.pointer.movement = .{ .relative = .{} };
    window.pointer.axis = .{};

    window.keyboard.progress();
    try window.call(.poll, .{options});
}

pub fn setTitle(window: *Window, title: [:0]const u8) !void {
    try window.call(.setTitle, .{title});
}

pub fn setMaxSize(window: *Window, size: ?Window.Size) !void {
    window.max_size = size;
    try window.call(.setMaxSize, .{size});
}

pub fn setMinSize(window: *Window, size: ?Window.Size) !void {
    window.min_size = size;
    try window.call(.setMinSize, .{size});
}

pub fn minimize(window: *Window) !void {
    try window.call(.minimize, .{});
}
pub fn maximize(window: *Window) !void {
    try window.call(.maximize, .{});
}
pub fn restore(window: *Window) !void {
    try window.call(.restore, .{});
}

pub fn setFullscreen(window: *Window, enabled: bool) !void {
    try window.call(.setFullscreen, .{enabled});
}

pub fn setPointerVisible(window: *Window, visible: bool) !void {
    if (window.pointer.visible == visible) return;
    window.pointer.visible = visible;
    try window.call(.setPointerVisible, .{visible});
}

pub fn setPointerConstraint(window: *Window, constraint: Pointer.Constraint) !void {
    if (window.pointer.constraint == constraint) return;
    window.pointer.constraint = constraint;
    try window.call(.setPointerConstraint, .{constraint});
}

pub fn setPointerRelative(window: *Window, enabled: bool) !void {
    if (window.pointer.is_relative == enabled) return;
    window.pointer.is_relative = enabled;
    window.pointer.movement = if (enabled) .{ .relative = .{} } else .{ .position = .{} };
    try window.call(.setPointerRelative, .{enabled});
}

/// icons must be square; `size` specifies both the width and height.
/// `bgra` must contain exactly `size * size * 4` bytes of BGRA8 pixel data.
pub fn setIcon(window: *Window, bgra: []const u8) !void {
    const channels = 4;
    const size: u32 = std.math.sqrt(@divExact(bgra.len, channels));
    std.debug.assert(size <= 256);
    try window.call(.setIcon, .{ size, bgra });
}

fn call(window: *Window, function_name: @EnumLiteral(), args: anytype) !void {
    switch (native_os) {
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => switch (window.inner) {
            inline else => |*inner| {
                const function = @field(@TypeOf(inner.*), @tagName(function_name));
                return @call(.always_inline, function, .{ inner, window } ++ args);
            },
        },
        else => {
            const inner = &window.inner;
            const function = @field(@TypeOf(window.inner), @tagName(function_name));
            return @call(.always_inline, function, .{ inner, window } ++ args);
        },
    }
}
