const Cocoa = @This();

const Window = @import("../Window.zig");

pub fn open(self: *Cocoa, window: *Window, options: Window.OpenOptions) !void {
    _ = options;
    _ = window;
    self.* = .{};
}
pub fn close(self: *Cocoa, window: *Window) void {
    _ = self;
    _ = window;
}
pub fn poll(self: *Cocoa, window: *Window) !void {
    _ = self;
    _ = window;
}
