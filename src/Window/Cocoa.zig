const Cocoa = @This();

// zig build -Dtarget=aarch64-macos && gh workflow run "macOS Build"

const std = @import("std");

const Window = @import("../Window.zig");

app: *cocoa.NSApplication,
window: *cocoa.NSWindow,
view: *cocoa.NSView,
metal_layer: *cocoa.CAMetalLayer,

pub fn open(self: *Cocoa, _: *Window, options: Window.OpenOptions) !void {
    const app = cocoa.applicationCreate();
    errdefer cocoa.applicationDestroy(app);

    const window = cocoa.windowCreate(app, .{
        .width = options.size.width,
        .height = options.size.height,
        .x = if (options.position) |position| position.x else undefined,
        .y = if (options.position) |position| position.y else undefined,
        .has_position = options.position != null,
    });
    errdefer cocoa.windowDestroy(window);

    const view = cocoa.windowGetView(window) orelse return error.GetView;
    const metal_layer = cocoa.windowGetMetalLayer(window) orelse return error.GetMetalLayer;

    cocoa.windowSetTitle(window, options.title);

    self.* = .{
        .app = app,
        .window = window,
        .view = view,
        .metal_layer = metal_layer,
    };
}

pub fn close(self: *Cocoa, _: *Window) void {
    cocoa.windowDestroy(self.window);
    cocoa.applicationDestroy(self.app);
}

pub fn poll(self: *Cocoa, window: *Window, options: Window.PollOptions) !void {
    var event: cocoa.Event = undefined;
    while (cocoa.applicationPollEvent(self.app, &event)) switch (event.type) {
        .close => window.should_close = true,

        .resize => {
            const size = event.data.resize;
            window.size = .{ .width = size.width, .height = size.height };
        },
        .move => {
            const position = event.data.move;
            window.position = .{ .x = position.x, .y = position.y };
        },

        .focus_gained => window.focused = true,
        .focus_lost => window.focused = false,

        .mouse_move => {
            const position = event.data.mouse_move;
            window.pointer.movement = .{ .position = .{
                .x = position.x,
                .y = position.y,
            } };
        },
        .mouse_button => {
            const b = &window.pointer.buttons;
            const state = event.data.mouse_button.pressed;
            switch (event.data.mouse_button.button) {
                0 => b.left = state,
                1 => b.right = state,
                2 => b.middle = state,
                3 => b.forward = state,
                4 => b.back = state,
                5 => b.extra1 = state,
                6 => b.extra2 = state,
                7 => b.extra3 = state,
                else => {
                    std.log.err("bad mouse button: {d}", .{event.data.mouse_button.button});
                },
            }
        },
        .mouse_scroll => {
            window.pointer.axis.horizontal += event.data.mouse_scroll.x;
            window.pointer.axis.vertical += event.data.mouse_scroll.y;
        },

        .key_down, .key_up => {
            const key = Window.Keyboard.fromCocoa(event.data.key.key_code) orelse {
                std.log.err("unknown keycode: {d}", .{event.data.key.key_code});
                continue;
            };

            switch (event.type) {
                .key_down => window.keyboard.press(key),
                .key_up => window.keyboard.release(key),
                else => unreachable,
            }

            if (event.data.key.repeat) {
                window.keyboard.previous.set(@intFromEnum(key));
            }
        },
        .text_input => {
            var writer = options.text orelse continue;
            const codepoint: u21 = @truncate(event.data.text_input.codepoint);
            var buffer: [8]u8 = undefined;
            const utf8 = buffer[0..try std.unicode.utf8Encode(codepoint, &buffer)];
            try writer.writeAll(utf8);
        },
    };
}

pub fn setTitle(self: *Cocoa, _: *Window, title: [:0]const u8) !void {
    cocoa.windowSetTitle(self.window, title.ptr);
}

pub fn setMaxSize(self: *Cocoa, _: *Window, size: ?Window.Size) !void {
    const width: cocoa.CGFloat = if (size) |s| @floatFromInt(s.width) else std.math.floatMax(cocoa.CGFloat);
    const height: cocoa.CGFloat = if (size) |s| @floatFromInt(s.height) else std.math.floatMax(cocoa.CGFloat);
    cocoa.windowSetMaxSize(self.window, width, height);
}

pub fn setMinSize(self: *Cocoa, _: *Window, size: ?Window.Size) !void {
    const width: cocoa.CGFloat = if (size) |s| @floatFromInt(s.width) else 0.0;
    const height: cocoa.CGFloat = if (size) |s| @floatFromInt(s.height) else 0.0;
    cocoa.windowSetMinSize(self.window, width, height);
}

pub fn minimize(self: *Cocoa, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn maximize(self: *Cocoa, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn restore(self: *Cocoa, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn setFullscreen(self: *Cocoa, window: *Window, enabled: bool) !void {
    _ = self;
    _ = window;
    _ = enabled;
}

pub fn setPointerVisible(self: *Cocoa, window: *Window, visible: bool) !void {
    _ = self;
    _ = window;
    _ = visible;
}

pub fn setPointerConstraint(self: *Cocoa, window: *Window, constraint: Window.Pointer.Constraint) !void {
    _ = self;
    _ = window;
    _ = constraint;
}

pub fn setPointerRelative(self: *Cocoa, window: *Window, enabled: bool) !void {
    _ = self;
    _ = window;
    _ = enabled;
}

pub fn setIcon(self: *Cocoa, window: *Window, size: u32, bgra: []const u8) !void {
    _ = self;
    _ = window;
    _ = size;
    _ = bgra;
}

const cocoa = struct {
    pub const NSApplication = opaque {};
    pub const NSWindow = opaque {
        pub const CreateInfo = extern struct {
            x: f64,
            y: f64,
            width: u32,
            height: u32,
            has_position: bool,
        };
    };
    pub const NSView = opaque {};
    pub const CAMetalLayer = opaque {};

    pub const CGFloat = if (@bitSizeOf(usize) == 64)
        f64
    else
        f32;

    pub const Event = extern struct {
        type: EventType,

        data: extern union {
            resize: extern struct {
                width: u32,
                height: u32,
            },
            move: extern struct {
                x: i32,
                y: i32,
            },

            mouse_move: extern struct {
                x: CGFloat,
                y: CGFloat,
            },
            mouse_button: extern struct {
                button: u32,
                pressed: bool,
            },
            mouse_scroll: extern struct {
                x: CGFloat,
                y: CGFloat,
            },

            key: extern struct {
                key_code: u32,
                pressed: bool,
                repeat: bool,
            },
            text_input: extern struct {
                codepoint: u32,
            },
        },

        pub const EventType = enum(c_int) {
            close,

            resize,
            move,

            focus_gained,
            focus_lost,

            mouse_move,
            mouse_button,
            mouse_scroll,

            key_down,
            key_up,
            text_input,
        };
    };

    pub extern fn applicationCreate() *NSApplication;
    pub extern fn applicationDestroy(app: *NSApplication) void;

    pub extern fn applicationPollEvent(app: *NSApplication, event: *Event) bool;

    pub extern fn windowCreate(app: *NSApplication, create_info: NSWindow.CreateInfo) *NSWindow;
    pub extern fn windowDestroy(window: *NSWindow) void;
    pub extern fn windowGetView(window: *NSWindow) ?*NSView;
    pub extern fn windowGetMetalLayer(window: *NSWindow) ?*CAMetalLayer;
    pub extern fn windowSetTitle(window: *NSWindow, title: [*:0]const u8) void;
    pub extern fn windowSetMaxSize(window: *NSWindow, width: CGFloat, height: CGFloat) void;
    pub extern fn windowSetMinSize(window: *NSWindow, width: CGFloat, height: CGFloat) void;
};
