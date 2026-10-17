const Metal = @This();

const std = @import("std");
const CA = @import("frameworks").CA;
const MTL = @import("frameworks").MTL;
const Window = @import("../Window.zig");

const Renderer = @import("../Renderer.zig");

metal_layer: *CA.MetalLayer,
device: *MTL.Device,
command_queue: *MTL.CommandQueue,

pub fn init(gpa: std.mem.Allocator, window: *Window) !Metal {
    _ = gpa;

    const metal_layer: *CA.MetalLayer = .new();

    const device: *MTL.Device = try .new();
    metal_layer.setDevice(device);

    const command_queue = try device.newCommandQueue();

    window.inner.view.setWantsLayer(true);
    window.inner.view.setLayer(metal_layer.super());

    return .{
        .metal_layer = metal_layer,
        .device = device,
        .command_queue = command_queue,
    };
}

pub fn deinit(self: *Metal) void {
    self.* = undefined;
}

pub const Frame = struct {
    drawable: *MTL.Drawable,
    command_buffer: *MTL.CommandBuffer,
    encoder: *MTL.RenderCommandEncoder,

    pub fn begin(m: *Metal, options: Renderer.Frame.BeginOptions) Renderer.Frame.BeginError!Frame {
        const drawable = m.metal_layer.nextDrawable() orelse return error.NoDrawable;

        m.metal_layer.setDrawableSize(.{
            .width = @floatFromInt(options.size.width),
            .height = @floatFromInt(options.size.height),
        });

        const command_buffer = m.command_queue.commandBuffer() orelse return error.CommandBufferUnavailable;

        const render_pass: *MTL.RenderPassDescriptor = .new();

        const attachment = render_pass
            .colorAttachments()
            .objectAtIndexedSubscript(0);

        attachment.setTexture(drawable.texture());
        attachment.setLoadAction(.clear);
        attachment.setStoreAction(.store);

        attachment.setClearColor(.{
            .red = options.clear_color[0],
            .green = options.clear_color[1],
            .blue = options.clear_color[2],
            .alpha = options.clear_color[3],
        });

        const encoder = command_buffer.renderCommandEncoder(render_pass);

        return .{
            .drawable = drawable,
            .command_buffer = command_buffer,
            .encoder = encoder,
        };
    }

    pub fn end(frame: Frame) !void {
        frame.encoder.endEncoding();
        frame.command_buffer.present(frame.drawable);
        frame.command_buffer.commit();
    }

    pub fn bindPipeline(frame: Frame, pipeline: GraphicsPipeline) void {
        frame.encoder.setRenderPipelineState(pipeline.handle);
    }

    pub fn drawMesh(frame: Frame, mesh: Mesh) void {
        frame.encoder.setVertexBuffer(mesh.vertex_buffer, 0, 0);

        frame.encoder.drawIndexedPrimitives(
            .triangle,
            mesh.index_count,
            .uint32,
            mesh.index_buffer,
            0,
        );
    }
};

pub const GraphicsPipeline = struct {
    handle: *MTL.RenderPipelineState,

    pub fn init(m: *Metal, options: Renderer.GraphicsPipeline.CreateOptions) !GraphicsPipeline {
        const pipeline_descriptor: *MTL.RenderPipelineDescriptor = .new();

        switch (options.shaders) {
            .separate => |separate| {
                _ = separate;
            },
            .combined => |combined| {
                const library = try m.device.newLibraryWithDataSlice(combined.source);
                defer library.release();

                const vertex = try library.newFunctionWithNameSlice(combined.vertex);
                pipeline_descriptor.setVertexFunction(vertex);

                if (combined.fragment) |fragment_entry| {
                    const fragment = try library.newFunctionWithNameSlice(fragment_entry);
                    pipeline_descriptor.setFragmentFunction(fragment);
                }

                if (combined.tessellation) |tessellation| {
                    const tessellation_control = try library.newFunctionWithNameSlice(tessellation.control);
                    const tessellation_evaluation = try library.newFunctionWithNameSlice(tessellation.evaluation);

                    // TODO:
                    _ = tessellation_control;
                    _ = tessellation_evaluation;
                }
            },
        }

        const color_attachment = pipeline_descriptor
            .colorAttachments()
            .objectAtIndexedSubscript(0);

        color_attachment.setPixelFormat(.bgra8Unorm);

        return .{ .handle = try m.device.newRenderPipelineState(pipeline_descriptor) };
    }

    pub fn deinit(pipeline: GraphicsPipeline, m: *Metal) void {
        _ = m;
        pipeline.handle.release();
    }
};

pub const Mesh = struct {
    vertex_buffer: *MTL.Buffer,
    index_buffer: *MTL.Buffer,
    index_count: u32,

    pub fn init(m: *Metal, comptime Vertex: type, vertices: []const Vertex, indices: []const u32) !Mesh {
        const vertex_buffer = try m.device.newBufferWithBytes(
            @ptrCast(vertices.ptr),
            vertices.len * @sizeOf(Vertex),
            .storage_mode_managed,
        );

        errdefer vertex_buffer.release();

        const index_buffer = try m.device.newBufferWithBytes(
            @ptrCast(indices.ptr),
            indices.len * @sizeOf(u32),
            .storage_mode_managed,
        );

        return .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .index_count = @intCast(indices.len),
        };
    }

    pub fn deinit(mesh: *const Mesh, _: *Metal) void {
        mesh.index_buffer.release();
        mesh.vertex_buffer.release();
    }
};
