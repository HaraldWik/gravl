const X = @This();

const Window = @import("../Window.zig");

pub fn open(self: *X, window: *Window, options: Window.OpenOptions) !void {
    _ = options;
    _ = window;
    self.* = .{};
}
pub fn close(self: *X, window: *Window) void {
    _ = self;
    _ = window;
}
pub fn poll(self: *X, window: *Window) !void {
    _ = self;
    _ = window;
}
