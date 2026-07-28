const Window = @This();

const builtin = @import("builtin");

const std = @import("std");

inner: Inner,

should_close: bool = false,
size: Size,
position: Position,
focused: bool = true,

pub const empty: Window = undefined;

pub const Inner = switch (builtin.os.tag) {
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
    movement: Movement,
    buttons: Buttons = .{},

    pub const Movement = union(enum) {
        position: struct {
            x: f64,
            y: f64,
        },
        relative: struct {
            dx: f64,
            dy: f64,
        },
    };

    pub const Buttons = packed struct {
        left: bool = false,
        middle: bool = false,
        right: bool = false,

        back: bool = false,
        forward: bool = false,

        extra1: bool = false,
        extra2: bool = false,
        extra3: bool = false,
    };
};

pub const OpenOptions = struct {
    app_id: ?@EnumLiteral() = null, // e.g my_app
    title: [:0]const u8,
    size: Size,
    position: ?Position = null,
};

pub fn open(self: *Window, init: std.process.Init, options: OpenOptions) !void {
    self.inner = switch (builtin.os.tag) {
        .linux => blk: {
            const session_type = LinuxSessionType.detect(init.minimal) orelse .x11;
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

    try self.call(.open, if (builtin.os.tag == .windows) .{ options, init.gpa } else .{options});
}

pub fn close(self: *Window) void {
    self.call(.close, .{}) catch unreachable;
    self.* = undefined;
}

pub fn poll(self: *Window) !void {
    try call(self, .poll, .{});
}
fn call(self: *Window, function_name: @EnumLiteral(), args: anytype) !void {
    switch (builtin.os.tag) {
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
