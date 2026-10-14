const Renderer = @This();

const builtin = @import("builtin");

const std = @import("std");

const Window = @import("Window.zig");
const Vulkan = @import("Renderer/Vulkan2.zig");
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

pub const Frame = struct {
    renderer: *Renderer,
    inner: InnerType.Frame,

    pub fn begin(r: *Renderer, size: Window.Size) !Frame {
        return .{
            .renderer = r,
            .inner = try .begin(&r.inner, size),
        };
    }

    pub fn end(frame: Frame) !void {
        try frame.inner.end(frame.renderer.inner);
    }
};

pub const GraphicsPipeline = struct {
    inner: InnerType.GraphicsPipeline,

    pub const Options = struct {
        vertex_shader: Shader,
        fragment_shader: ?Shader = null,

        tessellation: ?Tessellation = null,

        primitive_topology: PrimitiveTopology = .triangle_list,

        pub const Shader = struct {
            source: []const u8,
            entry_name: []const u8 = "main",
        };

        pub const Tessellation = struct {
            control_shader: Shader,
            evaluation_shader: Shader,
            patch_control_points: u32,
        };

        pub const PrimitiveTopology = enum {
            point_list,
            line_list,
            line_strip,
            triangle_list,
            triangle_strip,
            patch_list,
        };
    };

    pub fn create(r: *Renderer, options: Options) !GraphicsPipeline {
        _ = r;
        _ = options;
        // ...

    }
};
