const Wayland = @This();

const std = @import("std");

const Window = @import("../Window.zig");

const wl = @import("wayland").client.wl;
const wp = @import("wayland").client.wp;
const xdg = @import("wayland").client.xdg;
const zxdg = @import("wayland").client.zxdg;

window: *Window,

display: *wl.Display,

surface: *wl.Surface,
xdg_surface: *xdg.Surface,
toplevel: *xdg.Toplevel,

frame_callback: ?*wl.Callback = null,

pointer: ?*wl.Pointer = null,
keyboard: ?*wl.Keyboard = null,

pub fn open(self: *Wayland, window: *Window, options: Window.OpenOptions) !void {
    try Loader.load();

    self.window = window;

    const display = try wl.Display.connect(null);

    const registry = try display.getRegistry();
    defer registry.destroy();

    var registry_data: RegistryData = .{};
    registry.setListener(*RegistryData, RegistryData.listener, &registry_data);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const compositor = registry_data.compositor.?;
    const xdg_wm_base = registry_data.xdg_wm_base.?;
    const seat = registry_data.seat.?;

    seat.setListener(*Wayland, seatListener, self);

    if (display.flush() != .SUCCESS) return error.Flush;
    if (display.dispatch() != .SUCCESS) return error.Dispatch;

    const surface = try compositor.createSurface();
    const xdg_surface = try xdg_wm_base.getXdgSurface(surface);
    const toplevel = try xdg_surface.getToplevel();

    var configured: bool = false;
    surface.setListener(*Window, surfaceListener, window);
    xdg_surface.setListener(*bool, xdgSurfaceListener, &configured);
    toplevel.setListener(*Wayland, xdgToplevelListener, self);

    xdg_surface.setWindowGeometry(0, 0, @intCast(options.size.width), @intCast(options.size.height));

    if (options.app_id) |app_id| toplevel.setAppId(app_id.ptr);
    toplevel.setTitle(options.title.ptr);

    surface.commit();
    while (!configured) if (display.dispatch() != .SUCCESS) return error.Dispatch;
    surface.commit();

    self.* = .{
        .window = window,
        .display = display,
        .surface = surface,
        .xdg_surface = xdg_surface,
        .toplevel = toplevel,
    };
}

pub fn close(self: *Wayland, window: *Window) void {
    _ = window;
    if (self.pointer) |pointer| pointer.destroy();
    if (self.keyboard) |keyboard| keyboard.destroy();

    self.toplevel.destroy();
    self.xdg_surface.destroy();
    self.surface.destroy();

    self.display.disconnect();

    Loader.unload();
}

pub fn poll(self: *Wayland, window: *Window, options: Window.PollOptions) !void {
    const display = self.display;
    _ = options;

    if (window.should_close) return;

    while (display.prepareRead() == false) {
        if (display.dispatchPending() != .SUCCESS) return error.DispatchPending;
    }

    switch (display.flush()) {
        .SUCCESS, .AGAIN, .INTR => {},
        .PIPE => return error.CompositorDisconnected,
        else => return error.Flush,
    }

    var pfd: std.posix.pollfd = .{
        .fd = @intCast(display.getFd()),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };

    if (std.posix.poll(@ptrCast(&pfd), 1) catch 0 > 0) {
        if (display.readEvents() != .SUCCESS) return error.ReadEvents;
    } else {
        display.cancelRead();
    }

    if (display.dispatchPending() != .SUCCESS) return error.DispatchPending;
}
pub fn setTitle(self: *Wayland, window: *Window, title: [:0]const u8) !void {
    _ = window;
    self.toplevel.setTitle(title);
}

const RegistryData = struct {
    compositor: ?*wl.Compositor = null,
    xdg_wm_base: ?*xdg.WmBase = null,
    seat: ?*wl.Seat = null,
    wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1 = null,
    zxdg_decoration_manager: ?*zxdg.DecorationManagerV1 = null,

    pub fn listener(registry: *wl.Registry, event: wl.Registry.Event, self: *RegistryData) void {
        switch (event) {
            .global => |global| inline for (std.meta.fields(RegistryData)) |field| {
                const GlobalType = std.meta.Child(std.meta.Child(field.type));
                if (std.mem.orderZ(u8, global.interface, GlobalType.interface.name) == .eq) {
                    @field(self.*, field.name) = registry.bind(global.name, GlobalType, 1) catch return;
                    return;
                }
            },
            .global_remove => {},
        }
    }
};

fn surfaceListener(_: *wl.Surface, event: wl.Surface.Event, window: *Window) void {
    _ = window;
    switch (event) {
        .enter => {},
        .leave => {},
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, configured: *bool) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            configured.* = true;
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, self: *Wayland) void {
    const window = self.window;
    switch (event) {
        .configure => |configure| {
            for (configure.states.slice(xdg.Toplevel.State)) |state| switch (state) {
                .maximized => {},
                .fullscreen => {},
                .resizing => window.size = .{ .width = @intCast(configure.width), .height = @intCast(configure.height) },
                .activated => window.focused = true,
                .tiled_left => {},
                .tiled_right => {},
                .tiled_top => {},
                .tiled_bottom => {},
                _ => {},
            };
        },
        .close => window.should_close = true,
    }
}

fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, self: *Wayland) void {
    switch (event) {
        .capabilities => |capabilities| {
            if (capabilities.capabilities.pointer) {
                self.pointer = seat.getPointer() catch unreachable;
                self.pointer.?.setListener(*Wayland, pointerListener, self);
            } else if (self.pointer) |pointer| {
                pointer.release();
                self.pointer = null;
            }
            if (capabilities.capabilities.keyboard) {
                self.keyboard = seat.getKeyboard() catch unreachable;
                self.keyboard.?.setListener(*Wayland, keyboardListener, self);
            } else if (self.keyboard) |keyboard| {
                keyboard.release();
                self.keyboard = null;
            }
        },
        .name => {},
    }
}

fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, self: *Wayland) void {
    const window = self.window;
    switch (event) {
        .enter => {},
        .leave => {},
        .motion => |motion| {
            window.pointer.movement = .{ .position = .{
                .x = motion.surface_x.toDouble(),
                .y = motion.surface_y.toDouble(),
            } };
        },
        .button => |button| {
            const buttons = &window.*.pointer.buttons;
            const state = button.state == .pressed;
            switch (button.button) {
                0x110 => buttons.left = state,
                0x112 => buttons.middle = state,
                0x111 => buttons.right = state,
                0x113 => buttons.back = state,
                0x114 => buttons.forward = state,
                0x115 => buttons.extra1 = state,
                0x116 => buttons.extra2 = state,
                else => {},
            }
        },
        .axis => |axis| {
            switch (axis.axis) {
                .vertical_scroll => window.pointer.axis.vertical = -axis.value.toDouble() / 10.0,
                .horizontal_scroll => window.pointer.axis.horizontal = axis.value.toDouble() / 10.0,
                _ => unreachable,
            }
        },
    }
}

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, self: *Wayland) void {
    const window = self.window;
    const keyboard = &self.*.window.keyboard;

    switch (event) {
        .keymap => {},
        .enter => |enter| {
            window.focused = true;
            for (enter.keys.slice(u32)) |key| {
                std.log.info("key: {d}", .{key});
            }
        },
        .leave => window.focused = false,
        .key => |key| {
            const scancode = key.key + 30;

            const k: Window.Keyboard.Key = @enumFromInt((scancode) % Window.Keyboard.Key.count);

            switch (key.state) {
                .pressed => keyboard.press(k),
                .released => keyboard.release(k),
                _ => unreachable,
            }
        },
        .modifiers => {},
        .repeat_info => {},
    }
}

var loader: Loader = .{};
/// Loads the wayland-client at runtime
const Loader = struct {
    lib: std.DynLib = undefined,

    wl_display_cancel_read: ?*const fn (display: *wl.Display) callconv(.c) void = null,
    wl_display_connect_to_fd: ?*const fn (fd: c_int) callconv(.c) ?*wl.Display = null,
    wl_display_connect: ?*const fn (name: ?[*:0]const u8) callconv(.c) ?*wl.Display = null,
    wl_display_create_queue: ?*const fn (display: *wl.Display) callconv(.c) ?*wl.EventQueue = null,
    wl_display_disconnect: ?*const fn (display: *wl.Display) callconv(.c) void = null,
    wl_display_dispatch_pending: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_dispatch_queue_pending: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_dispatch_queue: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_dispatch: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_flush: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_get_error: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_get_fd: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_prepare_read_queue: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_prepare_read: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_read_events: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_roundtrip_queue: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_roundtrip: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_event_queue_destroy: ?*const fn (queue: *wl.EventQueue) callconv(.c) void = null,
    wl_proxy_add_dispatcher: ?*const fn (proxy: *wl.Proxy, dispatcher: *const wl.Proxy.DispatcherFn, implementation: ?*const anyopaque, data: ?*anyopaque) callconv(.c) c_int = null,
    wl_proxy_create: ?*const fn (factory: *wl.Proxy, interface: *const wl.Interface) callconv(.c) ?*wl.Proxy = null,
    wl_proxy_destroy: ?*const fn (proxy: *wl.Proxy) callconv(.c) void = null,
    wl_proxy_get_id: ?*const fn (proxy: *wl.Proxy) callconv(.c) u32 = null,
    wl_proxy_get_user_data: ?*const fn (proxy: *wl.Proxy) callconv(.c) ?*anyopaque = null,
    wl_proxy_get_version: ?*const fn (proxy: *wl.Proxy) callconv(.c) u32 = null,
    wl_proxy_marshal_array_constructor_versioned: ?*const fn (proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface, version: u32) callconv(.c) ?*wl.Proxy = null,
    wl_proxy_marshal_array_constructor: ?*const fn (proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface) callconv(.c) ?*wl.Proxy = null,
    wl_proxy_marshal_array: ?*const fn (proxy: *wl.Proxy, opcode: u32, args: ?[*]wl.Argument) callconv(.c) void = null,
    wl_proxy_set_queue: ?*const fn (proxy: *wl.Proxy, queue: *wl.EventQueue) callconv(.c) void = null,

    comptime {
        _ = exports;
    }

    const exports = struct {
        // zig fmt: off
        export fn wl_display_cancel_read(display: *wl.Display) void { loader.wl_display_cancel_read.?(display); }
        export fn wl_display_connect_to_fd(fd: c_int) ?*wl.Display { return loader.wl_display_connect_to_fd.?(fd); }
        export fn wl_display_connect(name: ?[*:0]const u8) ?*wl.Display { return loader.wl_display_connect.?(name); }
        export fn wl_display_create_queue(display: *wl.Display) ?*wl.EventQueue { return loader.wl_display_create_queue.?(display); }
        export fn wl_display_disconnect(display: *wl.Display) void { loader.wl_display_disconnect.?(display); }
        export fn wl_display_dispatch_pending(display: *wl.Display) c_int { return loader.wl_display_dispatch_pending.?(display); }
        export fn wl_display_dispatch_queue_pending(display: *wl.Display, queue: *wl.EventQueue) c_int { return loader.wl_display_dispatch_queue_pending.?(display, queue); }
        export fn wl_display_dispatch_queue(display: *wl.Display, queue: *wl.EventQueue) c_int { return loader.wl_display_dispatch_queue.?(display, queue); }
        export fn wl_display_dispatch(display: *wl.Display) c_int { return loader.wl_display_dispatch.?(display); }
        export fn wl_display_flush(display: *wl.Display) c_int { return loader.wl_display_flush.?(display); }
        export fn wl_display_get_error(display: *wl.Display) c_int { return loader.wl_display_get_error.?(display); }
        export fn wl_display_get_fd(display: *wl.Display) c_int { return loader.wl_display_get_fd.?(display); }
        export fn wl_display_prepare_read_queue(display: *wl.Display, queue: *wl.EventQueue) c_int { return loader.wl_display_prepare_read_queue.?(display, queue); }
        export fn wl_display_prepare_read(display: *wl.Display) c_int { return loader.wl_display_prepare_read.?(display); }
        export fn wl_display_read_events(display: *wl.Display) c_int { return loader.wl_display_read_events.?(display); }
        export fn wl_display_roundtrip_queue(display: *wl.Display, queue: *wl.EventQueue) c_int { return loader.wl_display_roundtrip_queue.?(display, queue); }
        export fn wl_display_roundtrip(display: *wl.Display) c_int { return loader.wl_display_roundtrip.?(display); }
        export fn wl_event_queue_destroy(queue: *wl.EventQueue) void { loader.wl_event_queue_destroy.?(queue); }
        export fn wl_proxy_add_dispatcher(proxy: *wl.Proxy, dispatcher: *const wl.Proxy.DispatcherFn, implementation: ?*const anyopaque, data: ?*anyopaque) c_int { return loader.wl_proxy_add_dispatcher.?(proxy, dispatcher, implementation, data); }
        export fn wl_proxy_create(factory: *wl.Proxy, interface: *const wl.Interface) ?*wl.Proxy { return loader.wl_proxy_create.?(factory, interface); }
        export fn wl_proxy_destroy(proxy: *wl.Proxy) void { loader.wl_proxy_destroy.?(proxy); }
        export fn wl_proxy_get_id(proxy: *wl.Proxy) u32 { return loader.wl_proxy_get_id.?(proxy); }
        export fn wl_proxy_get_user_data(proxy: *wl.Proxy) ?*anyopaque { return loader.wl_proxy_get_user_data.?(proxy); }
        export fn wl_proxy_get_version(proxy: *wl.Proxy) u32 { return loader.wl_proxy_get_version.?(proxy); }
        export fn wl_proxy_marshal_array_constructor_versioned(proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface, version: u32) ?*wl.Proxy { return loader.wl_proxy_marshal_array_constructor_versioned.?(proxy, opcode, args, interface, version); }
        export fn wl_proxy_marshal_array_constructor(proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface) ?*wl.Proxy { return loader.wl_proxy_marshal_array_constructor.?(proxy, opcode, args, interface); }
        export fn wl_proxy_marshal_array(proxy: *wl.Proxy, opcode: u32, args: ?[*]wl.Argument) void { loader.wl_proxy_marshal_array.?(proxy, opcode, args); }
        export fn wl_proxy_set_queue(proxy: *wl.Proxy, queue: *wl.EventQueue) void { loader.wl_proxy_set_queue.?(proxy, queue); }
        // zig fmt: on
    };

    fn load() !void {
        loader.lib = try .openZ("libwayland-client.so.0");
        inline for (std.meta.fields(@This())) |field| {
            if (field.type != std.DynLib) {
                @field(loader, field.name) = loader.lib.lookup(field.type, field.name) orelse @panic(field.name);
            }
        }
    }

    fn unload() void {
        loader.lib.close();
    }
};
