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
        try cls.addMethod(.registerName("keyDown:"), keyDown);
        try cls.addMethod(.registerName("keyUp:"), keyUp);
        try cls.addMethod(.registerName("flagsChanged:"), flagsChanged);
        try cls.addMethod(.registerName("mouseDown:"), mouseDown);
        try cls.addMethod(.registerName("mouseUp:"), mouseUp);
        try cls.addMethod(.registerName("rightMouseDown:"), rightMouseDown);
        try cls.addMethod(.registerName("rightMouseUp:"), rightMouseUp);
        try cls.addMethod(.registerName("mouseMoved:"), mouseMoved);
        try cls.addMethod(.registerName("mouseDragged:"), mouseDragged);
        try cls.addMethod(.registerName("scrollWheel:"), scrollWheel);

        cls.registerPair();

        return cls;
    }

    fn acceptsFirstResponder(_: *c.Object, _: *c.SEL) callconv(.c) bool {
        return true;
    }

    fn keyDown(_: *c.Object, _: *c.SEL, event: *NS.Event) callconv(.c) void {
        const key_code = c.msgSend(
            u16,
            event,
            "keyCode",
            .{},
        );

        const characters = c.msgSend(
            *NS.String,
            event,
            "characters",
            .{},
        );

        std.debug.print(
            "keyDown: keyCode={d}, utf8={s}\n",
            .{ key_code, characters.utf8() },
        );
    }

    fn keyUp(_: *c.Object, _: *c.SEL, event: *NS.Event) callconv(.c) void {
        const key_code = c.msgSend(
            u16,
            event,
            "keyCode",
            .{},
        );

        std.debug.print(
            "keyUp: keyCode={}\n",
            .{key_code},
        );
    }

    fn flagsChanged(_: *c.Object, _: *c.SEL, event: *NS.Event) callconv(.c) void {
        const key_code = c.msgSend(
            u16,
            event,
            "keyCode",
            .{},
        );

        const modifiers = c.msgSend(
            usize,
            event,
            "modifierFlags",
            .{},
        );

        std.debug.print(
            "flagsChanged: keyCode={} modifiers={}\n",
            .{ key_code, modifiers },
        );
    }

    fn mouseDown(_: *c.Object, _: *c.SEL, _: *NS.Event) callconv(.c) void {
        std.debug.print("mouseDown\n", .{});
    }

    fn mouseUp(_: *c.Object, _: *c.SEL, _: *NS.Event) callconv(.c) void {
        std.debug.print("mouseUp\n", .{});
    }

    fn rightMouseDown(_: *c.Object, _: *c.SEL, _: *NS.Event) callconv(.c) void {
        std.debug.print("rightMouseDown\n", .{});
    }

    fn rightMouseUp(_: *c.Object, _: *c.SEL, _: *NS.Event) callconv(.c) void {
        std.debug.print("rightMouseUp\n", .{});
    }

    fn mouseMoved(_: *c.Object, _: *c.SEL, event: *NS.Event) callconv(.c) void {
        const location = c.msgSend(
            NS.Point,
            event,
            "locationInWindow",
            .{},
        );

        const dx = c.msgSend(
            f64,
            event,
            "deltaX",
            .{},
        );

        const dy = c.msgSend(
            f64,
            event,
            "deltaY",
            .{},
        );

        std.debug.print(
            "mouseMoved: x={d} y={d} dx={d} dy={d}\n",
            .{
                location.x,
                location.y,
                dx,
                dy,
            },
        );
    }

    fn mouseDragged(_: *c.Object, _: *c.SEL, event: *NS.Event) callconv(.c) void {
        const location = c.msgSend(
            NS.Point,
            event,
            "locationInWindow",
            .{},
        );

        const dx = c.msgSend(
            f64,
            event,
            "deltaX",
            .{},
        );

        const dy = c.msgSend(
            f64,
            event,
            "deltaY",
            .{},
        );

        std.debug.print(
            "mouseDragged: x={d} y={d} dx={d} dy={d}\n",
            .{
                location.x,
                location.y,
                dx,
                dy,
            },
        );
    }

    fn scrollWheel(_: *c.Object, _: *c.SEL, event: *NS.Event) callconv(.c) void {
        const dx = c.msgSend(
            f64,
            event,
            "scrollingDeltaX",
            .{},
        );

        const dy = c.msgSend(
            f64,
            event,
            "scrollingDeltaY",
            .{},
        );

        std.debug.print(
            "scrollWheel: dx={d} dy={d}\n",
            .{ dx, dy },
        );
    }
};

app: *NS.Application,
window: *NS.Window,
view: *NS.View,
metal_layer: *CA.MetalLayer,

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

    const metal_layer: *CA.MetalLayer = .new();

    view.setWantsLayer(true);
    view.setLayer(metal_layer.toLayer());

    self.* = .{
        .app = app,
        .window = ns_window,
        .view = view,
        .metal_layer = metal_layer,
    };
}

pub fn close(self: *Cocoa, _: *Window) void {
    _ = self;
}

pub fn poll(self: *Cocoa, _: *Window, options: Window.PollOptions) !void {
    _ = options;

    while (self.app.nextEventMatchingMask(.any, .distantPast(), NS.RunLoop.default.*, true)) |event| {
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
    c.msgSend(void, self.window, .registerName("performZoom:"), .{@as(?*anyopaque, null)});
}

pub fn restore(self: *Cocoa, window: *Window) !void {
    _ = self;
    _ = window;
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
