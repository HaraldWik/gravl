const Renderer = @This();

const builtin = @import("builtin");

const std = @import("std");

const Window = @import("Window.zig");
const Vulkan = @import("Renderer/Vulkan.zig");
const Metal = @import("Renderer/Metal.zig");

inner: InnerType,

pub const InnerType = if (builtin.target.os.tag.isDarwin())
    Metal
else
    Vulkan;

pub fn init(gpa: std.mem.Allocator, window: *Window) !Renderer {
    const inner: InnerType = try .init(gpa, window);
    return .{ .inner = inner };
}

pub fn deinit(r: *Renderer) void {
    r.inner.deinit();
}

pub const Shader = struct {
    handle: Handle,

    pub const Handle = switch (InnerType) {
        Vulkan => *anyopaque,
        Metal => Metal.RenderPipeline,
    };

    pub fn initFromSlice(r: *Renderer, s: []const u8) Shader {
        return .{ .handle = r.inner.createShaders(s) };
    }
};
