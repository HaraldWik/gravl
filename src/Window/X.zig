const X = @This();

const std = @import("std");
const xcb = @import("xcb");

const Window = @import("../Window.zig");

libxcb: std.DynLib,
bs: xcb.BaseWrapper,
cr: xcb.CoreWrapper,

connection: xcb.Connection,
id: xcb.Window,

pub fn open(self: *X, window: *Window, options: Window.OpenOptions) !void {
    var libxcb = try std.DynLib.openZ("libxcb.so");
    errdefer libxcb.close();

    const bs: xcb.BaseWrapper = .load(&libxcb);
    const cr: xcb.CoreWrapper = .load(&libxcb);

    const connection = bs.connect(null, null) orelse return error.Connect;
    errdefer bs.disconnect(connection);
    if (bs.connectionHasError(connection) != 0) return error.Connect;

    const setup = bs.getSetup(connection);
    const screen = xcb.setupRootsIterator(setup).data.?.*;

    const window_id: xcb.Window = bs.generateId(connection);

    cr.createWindow(
        connection,
        0,
        window_id,
        screen.root,
        if (options.position) |position| @truncate(position.x) else 0,
        if (options.position) |position| @truncate(position.y) else 0,
        @truncate(options.size.width),
        @truncate(options.size.height),
        1,
        xcb.WINDOW_CLASS.copy_from_parent,
        screen.root_visual,
        xcb.CW.event_mask,
        &.{
            xcb.EVENT_MASK.exposure | xcb.EVENT_MASK.key_press | xcb.EVENT_MASK.key_release,
        },
    );

    // if (options.app_id) |app_id| {
    //     // e.g "gravl\x00Gravl\x00";

    //     var buffer: [200]u8 = @splat(0);
    //     var writer: std.Io.Writer = .fixed(&buffer);

    //     try writer.writeAll(app_id);
    //     try writer.writeByte(0);
    //     try writer.writeAll(app_id);
    //     try writer.writeByte(0);

    //     const wm_class: [:0]const u8 = @ptrCast(writer.buffered());

    //     _ = cr.changeProperty(
    //         connection,
    //         xcb.PROP_MODE.replace,
    //         window_handle,
    //         .{ .id = xcb.ATOM.wm_class },
    //         .{ .id = xcb.ATOM.string },
    //         8,
    //         @intCast(wm_class.len),
    //         @ptrCast(wm_class.ptr),
    //     );
    // }

    self.setTitle(window, options.title) catch unreachable;
    cr.mapWindow(connection, window_id);
    _ = bs.flush(connection);

    self.* = .{
        .libxcb = libxcb,
        .bs = bs,
        .cr = cr,
        .connection = connection,
        .id = window_id,
    };
}

pub fn close(self: *X, window: *Window) void {
    _ = window;

    self.cr.destroyWindow(self.connection, self.id);
    self.bs.disconnect(self.connection);
    self.libxcb.close();
    self.* = undefined;
}

pub fn poll(self: *X, window: *Window, options: Window.PollOptions) !void {
    _ = options;
    while (self.bs.pollForEvent(self.connection)) |event| {
        // defer xcb.freeEvent(event);
        switch (event.response_type & 0x7f) {
            xcb.Expose.opcode => {
                const expose: *xcb.Expose = @ptrCast(@alignCast(event));

                std.log.info("expose area: {d}x{d}", .{
                    expose.width,
                    expose.height,
                });

                window.size = .{ .width = expose.width, .height = expose.height };
            },
            xcb.ClientMessage.opcode => {
                // window close handling
                break;
            },
            xcb.KeyPress.opcode => {
                const key: *xcb.KeyPress = @ptrCast(@alignCast(event));

                std.log.info("key press: {d}", .{key.detail});
                std.log.info("state: {d}", .{key.state});
            },
            xcb.KeyRelease.opcode => {
                const key: *xcb.KeyRelease = @ptrCast(@alignCast(event));

                std.log.info("key release: {d}", .{key.detail});
                std.log.info("state: {d}", .{key.state});
            },

            else => {},
        }
    }
}

pub fn setTitle(self: *X, window: *Window, title: [:0]const u8) !void {
    _ = self;
    _ = window;
    _ = title;
    // self.cr.changeProperty(
    //     self.connection,
    //     xcb.PROP_MODE.replace,
    //     self.handle,
    //     .{ .id = xcb.ATOM.wm_name },
    //     .{ .id = xcb.ATOM.string },
    //     8,
    //     @intCast(title.len),
    //     @ptrCast(title.ptr),
    // );
}

pub fn minimize(self: *X, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn maximize(self: *X, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn restore(self: *X, window: *Window) !void {
    _ = self;
    _ = window;
}

pub fn setFullscreen(self: *X, window: *Window, enabled: bool) !void {
    _ = self;
    _ = window;
    _ = enabled;
}

pub fn setPointerVisible(self: *X, window: *Window, visible: bool) !void {
    _ = self;
    _ = window;
    _ = visible;
}

pub fn setPointerConstraint(self: *X, window: *Window, constraint: Window.Pointer.Constraint) !void {
    _ = self;
    _ = window;
    _ = constraint;
}

pub fn setPointerRelative(self: *X, window: *Window, enabled: bool) !void {
    _ = self;
    _ = window;
    _ = enabled;
}
