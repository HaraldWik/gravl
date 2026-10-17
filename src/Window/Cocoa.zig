const Cocoa = @This();

// zig build -Dtarget=aarch64-macos

const std = @import("std");
const c = @import("objc");
const NS = @import("frameworks").NS;
const CA = @import("frameworks").CA;

const Window = @import("../Window.zig");

const View = struct {
    pub fn class() !*c.Class {
        const superclass: *c.Class = try .get("NSView");

        const cls: *c.Class = try .allocatePair(
            superclass,
            "View",
            0,
        );

        try cls.addMethod(.registerName("acceptsFirstResponder"), acceptsFirstResponder);

        cls.registerPair();

        return cls;
    }

    fn acceptsFirstResponder(_: *c.Object, _: *c.SEL) callconv(.c) bool {
        return true;
    }
};

app: *NS.Application,
window: *NS.Window,
view: *NS.View,

pub fn open(self: *Cocoa, window: *Window, options: Window.OpenOptions) !void {
    const app: *NS.Application = .shared();

    _ = app.setActivationPolicy(.regular);
    app.finishLaunching();

    const view_class = try View.class();

    const ns_window: *NS.Window = .init(
        .alloc(),
        .{
            .origin = .{
                .x = 100, // TODO
                .y = 100, // TODO
            },
            .size = .{
                .width = @floatFromInt(options.size.width),
                .height = @floatFromInt(options.size.height),
            },
        },
        .{},
        .buffered,
        false,
    );

    ns_window.setTitleSlice(options.title.ptr);

    const window_delegate: NS.Window.Delegate = try .create(.{
        .@"windowShouldClose:" = windowShouldClose,
    }, *Window, window);

    const view: *NS.View = .initWithFrame(c.msgSend(
        *NS.View,
        view_class,
        "alloc",
        .{},
    ), .{
        .origin = .{
            .x = 0,
            .y = 0,
        },
        .size = .{
            .width = @floatFromInt(options.size.width),
            .height = @floatFromInt(options.size.height),
        },
    });

    ns_window.setAcceptsMouseMovedEvents(true);
    window_delegate.setAsDelegate(ns_window);

    ns_window.setContentView(view);

    ns_window.makeKeyAndOrderFront();
    _ = ns_window.makeFirstResponder(@ptrCast(view));

    app.activateIgnoringOtherApps(true);

    self.* = .{
        .app = app,
        .window = ns_window,
        .view = view,
    };
}

pub fn close(self: *Cocoa, _: *Window) void {
    _ = self;
}

pub fn poll(self: *Cocoa, window: *Window, options: Window.PollOptions) !void {
    const pointer = &window.pointer;
    while (self.app.nextEventMatchingMask(.any, .distantPast(), NS.RunLoop.default.*, true)) |event| {
        switch (event.type()) {
            .left_mouse_down => pointer.buttons.left = true,
            .left_mouse_up => pointer.buttons.left = false,
            .right_mouse_down => pointer.buttons.right = true,
            .right_mouse_up => pointer.buttons.right = false,
            .other_mouse_down, .other_mouse_up => {
                const button = event.buttonNumber();
                const state = event.type() == .other_mouse_down;

                switch (button) {
                    2 => pointer.buttons.middle = state,
                    3 => pointer.buttons.back = state,
                    4 => pointer.buttons.forward = state,
                    5 => pointer.buttons.extra1 = state,
                    6 => pointer.buttons.extra2 = state,
                    7 => pointer.buttons.extra3 = state,
                    else => {},
                }
            },
            .mouse_moved => {
                const delta_x = event.deltaX();
                const delta_y = event.deltaY();

                pointer.movement = .{ .position = .{ .x = delta_x, .y = delta_y } };
            },

            .key_down, .key_up => {
                const characters = std.mem.span(c.msgSend(
                    *NS.String,
                    event,
                    "characters",
                    .{},
                ).utf8());

                if (options.text) |text| try text.writeAll(characters);

                const key = std.meta.stringToEnum(Window.Keyboard.Key, characters) orelse {
                    std.log.warn("unknown key: {any}", .{characters});
                    continue;
                };

                switch (event.type()) {
                    .key_down => window.keyboard.press(key),
                    .key_up => window.keyboard.release(key),
                    else => unreachable,
                }
                // const key_code = c.msgSend(
                //     u16,
                //     event,
                //     "keyCode",
                //     .{},
                // );

            },
            .flags_changed => {
                const ModifierFlags = packed struct(u64) {
                    caps_lock: bool = false,
                    shift: bool = false,
                    control: bool = false,
                    option: bool = false,
                    command: bool = false,
                    numeric_pad: bool = false,
                    help: bool = false,
                    function: bool = false,
                    _pad0: u56 = 0,
                };

                const flags = c.msgSend(ModifierFlags, event, "modifierFlags", .{});

                std.log.info("{any}", .{flags});
            },

            else => {},
        }
        self.app.sendEvent(event);
    }
}

pub fn setTitle(self: *Cocoa, _: *Window, title: [:0]const u8) !void {
    self.window.setTitleSlice(title.ptr);
}

pub fn setMaxSize(self: *Cocoa, _: *Window, size: ?Window.Size) !void {
    const max_size: NS.Size = .{
        .width = if (size) |s| @floatFromInt(s.width) else std.math.floatMax(f64),
        .height = if (size) |s| @floatFromInt(s.height) else std.math.floatMax(f64),
    };
    self.window.setMaxSize(max_size);
}

pub fn setMinSize(self: *Cocoa, _: *Window, size: ?Window.Size) !void {
    const min_size: NS.Size = .{
        .width = if (size) |s| @floatFromInt(s.width) else 0.0,
        .height = if (size) |s| @floatFromInt(s.height) else 0.0,
    };
    self.window.setMinSize(min_size);
}

pub fn minimize(self: *Cocoa, _: *Window) !void {
    self.window.miniaturize();
}

pub fn maximize(self: *Cocoa, _: *Window) !void {
    c.msgSend(void, self.window, .registerName("performZoom:"), .{null});
}

pub fn restore(self: *Cocoa, _: *Window) !void {
    if (self.window.isMiniaturized()) {
        self.window.deminiaturize(null);
    } else if (self.window.isZoomed()) {
        self.window.zoom(null);
    }
}

pub fn setFullscreen(self: *Cocoa, _: *Window, enabled: bool) !void {
    const style_mask = c.msgSend(NS.Window.StyleMask, self.window, "styleMask", .{});
    if (style_mask.full_screen != enabled) self.window.toggleFullScreen(null);
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

// Delegate

fn windowShouldClose(object: *c.Object, _: c.SEL, _: *NS.Window) callconv(.c) bool {
    const window = object.getIndexedIvars(*Window).*;
    window.should_close = true;
    return window.should_close;
}
