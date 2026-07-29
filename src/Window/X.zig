const X = @This();

const std = @import("std");
const xcb = @import("xcb");

const Window = @import("../Window.zig");

connection: *xcb.Connection,
handle: xcb.Xid,

pub fn open(self: *X, window: *Window, options: Window.OpenOptions) !void {
    _ = window;

    const connection = xcb.connect(null, null) orelse return error.Connect;
    defer xcb.disconnect(connection);
    if (connection.has_error != 0) return error.Connect;

    const screen = xcb.setupRootsIterator(connection.setup).data.?.*;

    const window_handle: xcb.Window = try connection.generateId();

    xcb.createWindow(
        connection,
        0,
        window_handle,
        screen.root,
        if (options.position) |position| @truncate(position.x) else 0,
        if (options.position) |position| @truncate(position.y) else 0,
        @truncate(options.size.width),
        @truncate(options.size.height),
        1,
        xcb.window_class.copy_from_parent,
        screen.root_visual,
        xcb.cw.event_mask,
        &.{
            xcb.event_mask.exposure | xcb.event_mask.key_press | xcb.event_mask.key_release,
        },
    );

    self.* = .{ .connection = connection, .handle = window_handle };
}

pub fn close(self: *X, window: *Window) void {
    _ = window;
    xcb.destroyWindow(self.connection, self.handle);
    xcb.disconnect(self.connection);
}

pub fn poll(self: *X, window: *Window, options: Window.PollOptions) !void {
    _ = options;
    while (xcb.pollForEvent(self.connection)) |event| {
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
}
