const Cocoa = @This();

// zig build -Dtarget=aarch64-macos

const std = @import("std");

const Window = @import("../Window.zig");

app: *obj_c.Application,
window: *obj_c.Window,

pub fn open(self: *Cocoa, window: *Window, options: Window.OpenOptions) !void {
    _ = options;
    _ = window;

    const app = obj_c.applicationCreate();
    errdefer obj_c.applicationDestroy(app);

    const window_handle = obj_c.windowCreate(app);
    errdefer obj_c.windowDestroy(window_handle);

    self.* = .{
        .app = app,
        .window = window_handle,
    };
}

pub fn close(self: *Cocoa, _: *Window) void {
    obj_c.windowDestroy(self.window);
    obj_c.applicationDestroy(self.app);
}

pub fn poll(self: *Cocoa, window: *Window, options: Window.PollOptions) !void {
    var event: obj_c.Event = undefined;
    while (obj_c.applicationPollEvent(self.app, &event)) switch (event.type) {
        .close => window.should_close = true,

        .resize => {
            const size = event.resize;
            window.size = .{ .width = size.width, .height = size.height };
        },
        .move => {
            const position = event.move;
            window.position = .{ .x = position.x, .y = position.y };
        },

        .focus_gained => window.focused = true,
        .focus_lost => window.focused = false,

        .mouse_move => {
            const position = event.mouse_move;
            window.pointer.movement = .{ .position = .{
                .x = position.x,
                .y = position.y,
            } };
        },
        .mouse_button => {
            const b = &window.pointer.buttons;
            const state = event.mouse_button.pressed;
            switch (event.mouse_button.button) {
                0 => b.left = state,
                1 => b.right = state,
                2 => b.middle = state,
                3 => b.forward = state,
                4 => b.back = state,
                5 => b.extra1 = state,
                6 => b.extra2 = state,
                7 => b.extra3 = state,
                else => {
                    std.log.err("bad mouse button: {d}", .{event.mouse_button.button});
                },
            }
        },
        .mouse_scroll => {
            window.pointer.axis.horizontal += event.mouse_scroll.x;
            window.pointer.axis.vertical += event.mouse_scroll.y;
        },

        .key_down => {
            const key = Window.Keyboard.fromCocoa(event.key.key_code) orelse {
                std.log.err("unknown keycode: {d}", .{event.key.key_code});
                continue;
            };

            window.keyboard.press(key);

            if (event.key.repeat) {
                window.keyboard.previous.set(@intFromEnum(key));
            }
        },

        .key_up => {
            const key = Window.Keyboard.fromCocoa(event.key.key_code) orelse {
                std.log.err("unknown keycode: {d}", .{event.key.key_code});
                continue;
            };

            window.keyboard.release(key);
        },
        .text_input => {
            var writer = options.text orelse continue;
            const codepoint: u21 = @truncate(event.text_input.codepoint);
            var buffer: [8]u8 = undefined;
            const utf8 = buffer[0..try std.unicode.utf8Encode(codepoint, buffer)];
            try writer.writeAll(utf8);
        },
    };
}

pub fn setTitle(self: *Cocoa, _: *Window, title: [:0]const u8) !void {
    obj_c.windowSetTitle(self.window, title.ptr);
}

pub fn setMaxSize(self: *Cocoa, window: *Window, size: ?Window.Size) !void {
    _ = self;
    _ = window;
    _ = size;
}

pub fn setMinSize(self: *Cocoa, window: *Window, size: ?Window.Size) !void {
    _ = self;
    _ = window;
    _ = size;
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

const obj_c = struct {
    pub const Application = opaque {};
    pub const Window = opaque {};

    pub const Event = extern union {
        type: EventType,

        resize: extern struct {
            width: u32,
            height: u32,
        },
        move: extern struct {
            x: i32,
            y: i32,
        },

        mouse_move: extern struct {
            x: f64,
            y: f64,
        },
        mouse_button: extern struct {
            button: u32,
            pressed: bool,
        },
        mouse_scroll: extern struct {
            x: f64,
            y: f64,
        },

        key: extern struct {
            key_code: u32,
            pressed: bool,
            repeat: bool,
        },
        text_input: extern struct {
            codepoint: u32,
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
    pub extern fn applicationCreate() *Application;
    pub extern fn applicationDestroy(app: *Application) void;

    pub extern fn applicationPollEvent(app: *Application, event: *Event) bool;

    pub extern fn windowCreate(app: *Application) *obj_c.Window;
    pub extern fn windowDestroy(window: *obj_c.Window) void;
    pub extern fn windowSetTitle(window: *obj_c.Window, title: [*:0]const u8) void;
};
