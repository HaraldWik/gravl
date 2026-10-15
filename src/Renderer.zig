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
    inner: InnerType.Frame,

    pub const BeginOptions = struct {
        size: Window.Size,
        clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    };

    pub const BeginError = error{
        NoDrawable,
        CommandBufferUnavailable,
    };

    pub fn begin(r: *Renderer, options: BeginOptions) if (InnerType == Metal) BeginError!Frame else anyerror!Frame {
        return .{ .inner = try .begin(&r.inner, options) };
    }

    pub fn end(frame: Frame) !void {
        try frame.inner.end();
    }

    pub fn bindPipeline(frame: Frame, pipeline: GraphicsPipeline) void {
        frame.inner.bindPipeline(pipeline.inner);
    }

    pub fn drawMesh(frame: Frame, mesh: Mesh) void {
        frame.inner.drawMesh(mesh.inner);
    }
};

pub const GraphicsPipeline = struct {
    inner: InnerType.GraphicsPipeline,

    pub const PrimitiveTopology = enum {
        point_list,
        line_list,
        line_strip,
        triangle_list,
        triangle_strip,
        patch_list,
    };

    pub const CreateOptions = struct {
        shaders: ShaderSource,

        primitive_topology: PrimitiveTopology = .triangle_list,

        pub const ShaderSource = union(enum) {
            separate: SeparateShaders,
            combined: CombinedShader,

            pub const SeparateShaders = struct {
                vertex: Shader,
                fragment: ?Shader = null,
                tessellation: ?Tessellation = null,

                pub const Tessellation = struct {
                    control: Shader,
                    evaluation: Shader,
                    patch_control_points: u32,
                };
            };

            pub const CombinedShader = struct {
                source: [:0]const u8,
                /// Name of the vertex shader entry point.
                vertex: [:0]const u8 = "vertex_main",
                /// Name of the fragment shader entry point, or `null` if absent.
                fragment: ?[:0]const u8 = null,
                tessellation: ?Tessellation = null,

                pub const Tessellation = struct {
                    control: [:0]const u8,
                    evaluation: [:0]const u8,
                    patch_control_points: u32,
                };
            };
        };

        pub const Shader = struct {
            source: [:0]const u8,
            entry: [:0]const u8 = "main",
        };
    };

    pub fn init(r: *Renderer, options: CreateOptions) !GraphicsPipeline {
        return .{ .inner = try .init(&r.inner, options) };
    }

    pub fn deinit(pipeline: GraphicsPipeline, r: *Renderer) void {
        pipeline.inner.deinit(&r.inner);
    }
};

pub const Mesh = struct {
    inner: InnerType.Mesh,

    pub fn init(r: *Renderer, comptime Vertex: type, vertices: []const Vertex, indices: []const u32) !Mesh {
        return .{ .inner = try .init(&r.inner, Vertex, vertices, indices) };
    }

    pub fn deinit(mesh: Mesh, r: *Renderer) void {
        mesh.inner.deinit(&r.inner);
    }
};
