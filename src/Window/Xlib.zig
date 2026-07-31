const Xlib = @This();

const std = @import("std");

const Window = @import("../Window.zig");

display: *xlib.Display,
id: xlib.Window,
wm_delete: xlib.Atom,

/// X Input Method,
xim: *xlib.XIM,
/// X Input Context,
xic: *xlib.XIC,

pub fn open(self: *Xlib, window: *Window, options: Window.OpenOptions) !void {
    try xlib.ProcTable.load();
    _ = options;
    _ = window;

    const display = xlib.procs.XOpenDisplay.?(null) orelse return error.OpenDisplay;
    errdefer _ = xlib.procs.XCloseDisplay.?(display);

    const screen = xlib.procs.XDefaultScreen.?(display);
    const root = xlib.procs.XRootWindow.?(display, screen);

    const window_id = xlib.procs.XCreateSimpleWindow.?(
        display,
        root,
        100, // x
        100, // y
        800, // width
        600, // height
        0, // border width
        0, // border color
        0, // background color
    );

    const event_mask: xlib.Event.Mask = .{
        .exposure = true,
        .structure_notify = true,

        .key_press = true,
        .key_release = true,
        .button_press = true,
        .button_release = true,
        .pointer_motion = true,
        .enter_window = true,
        .leave_window = true,
        .focus_change = true,
    };

    _ = xlib.procs.XSelectInput.?(
        display,
        window_id,
        event_mask,
    );

    _ = xlib.procs.XMapWindow.?(display, window_id);

    var wm_delete = xlib.procs.XInternAtom.?(
        display,
        "WM_DELETE_WINDOW",
        xlib.FALSE,
    );

    _ = xlib.procs.XSetWMProtocols.?(
        display,
        window_id,
        &wm_delete,
        1,
    );

    const xim = xlib.procs.XOpenIM.?(
        display,
        null,
        null,
        null,
    ) orelse return error.OpenInputMethod;
    errdefer _ = xlib.procs.XCloseIM.?(xim);

    const xic = xlib.procs.XCreateIC.?(
        xim,
        xlib.XN.InputStyle,
        @as(c_ulong, xlib.XIM.PreeditNothing | xlib.XIM.StatusNothing),

        xlib.XN.ClientWindow,
        @as(xlib.Window, window_id),

        xlib.XN.FocusWindow,
        @as(xlib.Window, window_id),

        @as(?*anyopaque, null),
    ) orelse return error.CreateInputContext;
    errdefer _ = xlib.procs.XDestroyIC.?(self.xic);

    _ = xlib.procs.XFlush.?(display);

    self.* = .{
        .display = display,
        .id = window_id,
        .wm_delete = wm_delete,
        .xim = xim,
        .xic = xic,
    };
}

pub fn close(self: *Xlib, _: *Window) void {
    const display = self.display;

    _ = xlib.procs.XDestroyIC.?(self.xic);
    _ = xlib.procs.XCloseIM.?(self.xim);
    _ = xlib.procs.XDestroyWindow.?(display, self.id);
    _ = xlib.procs.XCloseDisplay.?(display);

    xlib.ProcTable.unload();
}

pub fn poll(self: *Xlib, window: *Window, options: Window.PollOptions) !void {
    const display = self.display;

    const pointer = &window.pointer;
    const keyboard = &window.keyboard;

    while (xlib.procs.XPending.?(display) > 0) {
        var event: xlib.Event = undefined;
        if (xlib.procs.XNextEvent.?(display, &event) != 0) return error.NextEvent;

        switch (event.type) {
            .client_message => {
                const client = event.client;
                if (client.data.l[0] == self.wm_delete) window.should_close = true;
            },

            .expose => {
                const expose = event.expose;
                const size: Window.Size = .{ .width = @intCast(expose.width), .height = @intCast(expose.height) };
                const position: Window.Position = .{ .x = @intCast(expose.x), .y = @intCast(expose.y) };
                window.size = size;
                window.position = position;
                std.log.info("{any} {any}", .{ size, position });
            },
            .configure_notify => {
                const configure = event.configure;
                // const size: Window.Size = .{ .width = @intCast(configure.width), .height = @intCast(configure.height) };
                const position: Window.Position = .{ .x = @intCast(configure.x), .y = @intCast(configure.y) };
                // window.size = size;
                window.position = position;
            },

            .focus_in => window.focused = true,
            .focus_out => window.focused = false,

            .motion_notify => {
                const motion = event.motion;
                pointer.movement = .{ .position = .{
                    .x = @floatFromInt(motion.x),
                    .y = @floatFromInt(motion.y),
                } };
            },
            .button_press, .button_release => {
                const b = &pointer.buttons;

                const button = event.button;
                const state = event.type == .button_press;

                switch (button.button) {
                    1 => b.left = state,
                    2 => b.middle = state,
                    3 => b.right = state,
                    4...7 => if (event.type == .button_press) switch (button.button) {
                        4 => pointer.axis.vertical += 1,
                        5 => pointer.axis.vertical -= 1,
                        6 => pointer.axis.horizontal -= 1,
                        7 => pointer.axis.horizontal += 1,
                        else => unreachable,
                    },
                    8 => b.back = state,
                    9 => b.forward = state,
                    10 => b.extra1 = state,
                    11 => b.extra2 = state,
                    12 => b.extra3 = state,
                    else => {}, // unknown/extra button
                }
            },
            .key_press => {
                var keysym = xlib.procs.XLookupKeysym.?(&event.key, 0);
                if (Window.Keyboard.fromXkb(@enumFromInt(keysym))) |key| {
                    keyboard.press(key);
                }

                const writer = options.text orelse continue;

                var buffer: [128]u8 = undefined;
                var status: xlib.Status = .none;

                const len = xlib.procs.Xutf8LookupString.?(
                    self.xic,
                    &event.key,
                    &buffer,
                    buffer.len,
                    &keysym,
                    &status,
                );

                if (len > 0) {
                    const text = buffer[0..@intCast(len)];
                    try writer.writeAll(text);
                }
            },
            .key_release => {
                const keysym = xlib.procs.XLookupKeysym.?(&event.key, 0);
                const key = Window.Keyboard.fromXkb(@enumFromInt(keysym)) orelse continue;
                keyboard.release(key);
            },
            else => std.log.info("{t}", .{event.type}),
        }
    }
}

pub fn setTitle(self: *Xlib, window: *Window, title: [:0]const u8) !void {
    _ = self;
    _ = window;
    _ = title;
}

pub fn minimize(self: *Xlib, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn maximize(self: *Xlib, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn restore(self: *Xlib, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn setFullscreen(self: *Xlib, window: *Window, enabled: bool) !void {
    _ = self;
    _ = window;
    _ = enabled;
}

pub fn setPointerVisible(self: *Xlib, window: *Window, visible: bool) !void {
    _ = self;
    _ = window;
    _ = visible;
}

pub fn setPointerConstraint(self: *Xlib, window: *Window, constraint: Window.Pointer.Constraint) !void {
    _ = self;
    _ = window;
    _ = constraint;
}

pub fn setPointerRelative(self: *Xlib, window: *Window, enabled: bool) !void {
    _ = self;
    _ = window;
    _ = enabled;
}

const xlib = struct {
    pub const Display = opaque {};
    pub const XIM = opaque {
        pub const PreeditNothing: c_long = 0x0008;
        pub const StatusNothing: c_long = 0x0400;
    };
    pub const XrmDatabase = opaque {};
    pub const XIC = opaque {};
    pub const Window = c_ulong;
    pub const Atom = c_ulong;
    pub const Time = c_ulong;
    pub const KeySym = c_ulong;

    pub const Bool = c_int;
    pub const TRUE: Bool = 1;
    pub const FALSE: Bool = 0;

    pub const XN = struct {
        pub const InputStyle = "inputStyle";
        pub const ClientWindow = "clientWindow";
        pub const FocusWindow = "focusWindow";
    };

    pub const Status = enum(c_int) {
        none = 0,
        chars = 1,
        keysym = 2,
        both = 3,
        _,
    };

    pub const ComposeStatus = extern struct {
        compose_ptr: ?*anyopaque,
        chars_matched: c_int,
    };

    pub const Event = extern union {
        type: Type,

        key: Key,
        button: Button,
        motion: Motion,
        crossing: Crossing,
        focus: Focus,
        configure: Configure,
        client: ClientMessage,
        expose: Expose,
        destroy: DestroyWindow,
        map: Map,
        unmap: Unmap,

        pub const Type = enum(c_int) {
            /// Not delivered through XNextEvent; X errors use XErrorEvent
            error_event = 0,
            /// Not an event; protocol reply
            reply = 1,
            key_press = 2,
            key_release = 3,
            button_press = 4,
            button_release = 5,
            motion_notify = 6,
            enter_notify = 7,
            leave_notify = 8,
            focus_in = 9,
            focus_out = 10,
            keymap_notify = 11,
            expose = 12,
            graphics_expose = 13,
            no_expose = 14,
            visibility_notify = 15,
            create_notify = 16,
            destroy_notify = 17,
            unmap_notify = 18,
            map_notify = 19,
            map_request = 20,
            reparent_notify = 21,
            configure_notify = 22,
            configure_request = 23,
            gravity_notify = 24,
            resize_request = 25,
            circulate_notify = 26,
            circulate_request = 27,
            property_notify = 28,
            selection_clear = 29,
            selection_request = 30,
            selection_notify = 31,
            colormap_notify = 32,
            client_message = 33,
            mapping_notify = 34,
            generic_event = 35,
            _,
        };

        pub const Mask = packed struct(c_long) {
            key_press: bool = false,
            key_release: bool = false,
            button_press: bool = false,
            button_release: bool = false,
            enter_window: bool = false,
            leave_window: bool = false,
            pointer_motion: bool = false,
            pointer_motion_hint: bool = false,
            button_1_motion: bool = false,
            button_2_motion: bool = false,
            button_3_motion: bool = false,
            button_4_motion: bool = false,
            button_5_motion: bool = false,
            button_motion: bool = false,
            keymap_state: bool = false,
            exposure: bool = false,
            visibility_change: bool = false,
            structure_notify: bool = false,
            resize_redirect: bool = false,
            substructure_notify: bool = false,
            substructure_redirect: bool = false,
            focus_change: bool = false,
            property_change: bool = false,
            colormap_change: bool = false,
            owner_grab_button: bool = false,

            _: if (@bitSizeOf(c_ulong) == 32) u7 else u39 = 0,
        };

        pub const Key = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            window: xlib.Window,
            root: xlib.Window,
            subwindow: xlib.Window,
            time: Time,
            x: c_int,
            y: c_int,
            x_root: c_int,
            y_root: c_int,
            state: c_uint,
            keycode: c_uint,
            same_screen: Bool,
        };

        pub const Button = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            window: xlib.Window,
            root: xlib.Window,
            subwindow: xlib.Window,
            time: Time,
            x: c_int,
            y: c_int,
            x_root: c_int,
            y_root: c_int,
            state: c_uint,
            button: c_uint,
            same_screen: Bool,
        };

        pub const Motion = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            window: xlib.Window,
            root: xlib.Window,
            subwindow: xlib.Window,
            time: Time,
            x: c_int,
            y: c_int,
            x_root: c_int,
            y_root: c_int,
            state: c_uint,
            is_hint: u8,
            same_screen: Bool,
        };

        pub const Crossing = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            window: xlib.Window,
            root: xlib.Window,
            subwindow: xlib.Window,
            time: Time,
            x: c_int,
            y: c_int,
            x_root: c_int,
            y_root: c_int,
            mode: c_int,
            detail: c_int,
            same_screen: Bool,
            focus: Bool,
            state: c_uint,
        };

        pub const Focus = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            window: xlib.Window,
            mode: c_int,
            detail: c_int,
        };

        pub const Configure = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            event: xlib.Window,
            window: xlib.Window,
            x: c_int,
            y: c_int,
            width: c_int,
            height: c_int,
            border_width: c_int,
            above: xlib.Window,
            override_redirect: Bool,
        };

        pub const ClientMessage = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            window: xlib.Window,
            message_type: Atom,
            format: c_int,
            data: extern union {
                b: [20]u8,
                s: [10]i16,
                l: [5]c_long,
            },
        };

        pub const Expose = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            window: xlib.Window,
            x: c_int,
            y: c_int,
            width: c_int,
            height: c_int,
            count: c_int,
        };

        pub const DestroyWindow = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            event: xlib.Window,
            window: xlib.Window,
        };

        pub const Map = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            event: xlib.Window,
            window: xlib.Window,
            override_redirect: Bool,
        };

        pub const Unmap = extern struct {
            type: c_int,
            serial: c_ulong,
            send_event: Bool,
            display: *Display,
            event: xlib.Window,
            window: xlib.Window,
            from_configure: Bool,
        };
    };

    pub var procs: ProcTable = undefined;
    const ProcTable = struct {
        lib: std.DynLib = undefined,

        XOpenDisplay: ?*const fn (?[*:0]const u8) callconv(.c) ?*Display,
        XCloseDisplay: ?*const fn (*Display) callconv(.c) c_int,

        XDefaultScreen: ?*const fn (*Display) callconv(.c) c_int,
        XRootWindow: ?*const fn (*Display, c_int) callconv(.c) xlib.Window,

        XCreateSimpleWindow: ?*const fn (
            *Display,
            xlib.Window,
            c_int,
            c_int,
            c_uint,
            c_uint,
            c_uint,
            c_ulong,
            c_ulong,
        ) callconv(.c) xlib.Window,

        XDestroyWindow: ?*const fn (*Display, xlib.Window) callconv(.c) c_int,

        XMapWindow: ?*const fn (*Display, xlib.Window) callconv(.c) c_int,
        XUnmapWindow: ?*const fn (*Display, xlib.Window) callconv(.c) c_int,

        XSelectInput: ?*const fn (*Display, xlib.Window, Event.Mask) callconv(.c) c_int,

        XNextEvent: ?*const fn (*Display, *Event) callconv(.c) c_int,
        XPending: ?*const fn (*Display) callconv(.c) c_int,

        XFlush: ?*const fn (*Display) callconv(.c) c_int,
        XSync: ?*const fn (*Display, Bool) callconv(.c) c_int,

        XInternAtom: ?*const fn (*Display, [*:0]const u8, Bool) callconv(.c) Atom,

        XSetWMProtocols: ?*const fn (*Display, xlib.Window, *Atom, c_int) callconv(.c) c_int,

        XLookupKeysym: ?*const fn (*Event.Key, c_int) callconv(.c) KeySym,

        XOpenIM: ?*const fn (*Display, ?*XrmDatabase, ?[*:0]const u8, ?[*:0]const u8) callconv(.c) ?*XIM,
        XCloseIM: ?*const fn (*XIM) callconv(.c) Bool,
        XCreateIC: ?*const fn (*XIM, ...) callconv(.c) ?*XIC,
        XDestroyIC: ?*const fn (*XIC) callconv(.c) void,
        Xutf8LookupString: ?*const fn (*XIC, *Event.Key, [*]u8, c_int, *KeySym, *Status) callconv(.c) c_int,

        XQueryPointer: ?*const fn (
            *Display,
            xlib.Window,
            *xlib.Window,
            *xlib.Window,
            *c_int,
            *c_int,
            *c_int,
            *c_int,
            *c_uint,
        ) callconv(.c) Bool,

        XWarpPointer: ?*const fn (
            *Display,
            xlib.Window,
            xlib.Window,
            c_int,
            c_int,
            c_uint,
            c_uint,
            c_int,
            c_int,
        ) callconv(.c) c_int,

        XDefineCursor: ?*const fn (
            *Display,
            xlib.Window,
            c_ulong,
        ) callconv(.c) c_int,

        XUndefineCursor: ?*const fn (
            *Display,
            xlib.Window,
        ) callconv(.c) c_int,

        fn load() !void {
            procs.lib = try .openZ("libX11.so");

            inline for (std.meta.fields(ProcTable)) |field| {
                if (field.type == std.DynLib)
                    continue;

                @field(procs, field.name) =
                    procs.lib.lookup(field.type, field.name) orelse return error.MissingSymbol;
            }
        }

        fn unload() void {
            procs.lib.close();
        }
    };
};
