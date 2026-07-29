const Window = @This();

const native_os = @import("builtin").os.tag;

const std = @import("std");

inner: Inner,

should_close: bool = false,
size: Size,
position: Position,
focused: bool = true,
pointer: Pointer = .{},
keyboard: Keyboard = .{},

pub const empty: Window = undefined;

pub const Inner = switch (native_os) {
    .linux, .freebsd, .netbsd, .openbsd => union(LinuxSessionType) {
        wayland: @import("Window/Wayland.zig"),
        x11: @import("Window/X.zig"),
    },
    .windows => @import("Window/Win32.zig"),
    .macos => @import("Window/Cocoa.zig"),
    else => struct {
        const open = @compileError("unsupported platform");
        const close = @compileError("unsupported platform");
        const poll = @compileError("unsupported platform");
        const setTitle = @compileError("unsupported platform");
    },
};

const LinuxSessionType = enum(u2) {
    wayland,
    x11,

    pub const env = "XDG_SESSION_TYPE";

    pub fn detect(init: std.process.Init.Minimal) ?@This() {
        var args = init.args.iterate();
        _ = args.skip();

        const session = while (args.next()) |arg| {
            const identifier = "--xdg=";
            if (!std.mem.startsWith(u8, arg, identifier)) continue;
            break arg[identifier.len..];
        } else init.environ.getPosix(env) orelse return null;

        return std.meta.stringToEnum(@This(), session) orelse null;
    }
};

pub const Size = packed struct(u64) {
    width: u32 = 0,
    height: u32 = 0,

    pub fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }

    pub fn aspect(self: Size) f32 {
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }

    /// Coercible into @Vector(2, u32) or [2]u32
    pub fn toTuple(self: Size) struct { u32, u32 } {
        return .{ self.width, self.height };
    }
};

pub const Position = packed struct(i64) {
    x: i32 = 0,
    y: i32 = 0,

    pub fn eql(a: Position, b: Position) bool {
        return a.x == b.x and a.y == b.y;
    }

    /// Coercible into @Vector(2, i32) or [2]i32
    pub fn toTuple(self: Position) struct { i32, i32 } {
        return .{ self.x, self.y };
    }
};

pub const Pointer = struct {
    movement: Movement = .{ .position = .{} },
    buttons: Buttons = .{},
    axis: Axis = .{},

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

    pub const Axis = struct {
        horizontal: f64 = 0,
        vertical: f64 = 0,
    };
};

pub const Keyboard = @import("Window/Keyboard.zig");

pub const OpenOptions = struct {
    app_id: ?[:0]const u8 = null, // e.g "my_app"
    title: [:0]const u8,
    size: Size,
    position: ?Position = null,
};

pub fn open(self: *Window, gpa: std.mem.Allocator, init: std.process.Init.Minimal, options: OpenOptions) !void {
    self.inner = switch (native_os) {
        .linux, .freebsd, .netbsd, .openbsd => blk: {
            const session_type = LinuxSessionType.detect(init) orelse .x11;
            switch (session_type) {
                inline else => |inline_session_type| break :blk @unionInit(Inner, @tagName(inline_session_type), undefined),
            }
        },
        else => undefined,
    };

    self.* = .{
        .inner = self.inner,
        .size = options.size,
        .position = options.position orelse .{ .x = 0, .y = 0 },
    };

    try self.call(.open, if (native_os == .windows) .{ options, gpa } else .{options});
}

pub fn close(self: *Window) void {
    self.call(.close, .{}) catch unreachable;
    self.* = undefined;
}

pub const PollOptions = struct {
    text: ?*std.Io.Writer = null,
};

pub fn poll(self: *Window, options: PollOptions) !void {
    if (!self.focused) {
        self.pointer.buttons = .{};
        self.keyboard = .{};
    }

    if (self.pointer.movement == .relative) self.pointer.movement = .{ .relative = .{} };
    self.pointer.axis = .{};

    try self.call(.poll, .{options});

    var kb_it = self.keyboard.iterator();
    while (kb_it.next()) |entry| {
        const key, const state = entry;

        if (state == .press) self.keyboard.set(key, .repeat);
    }
}

pub fn setTitle(self: *Window, title: [:0]const u8) !void {
    try self.call(.setTitle, .{title});
}

fn call(self: *Window, function_name: @EnumLiteral(), args: anytype) !void {
    switch (native_os) {
        .linux, .freebsd, .netbsd, .openbsd => switch (self.inner) {
            inline else => |*inner| {
                const function = @field(@TypeOf(inner.*), @tagName(function_name));
                return @call(.always_inline, function, .{ inner, self } ++ args);
            },
        },
        else => {
            const function = @field(@TypeOf(self.inner), @tagName(function_name));
            return @call(.always_inline, function, .{ &self.inner, self } ++ args);
        },
    }
}
