const Metal = @This();

const std = @import("std");
const CA = @import("objc").CA;
const MTL = @import("objc").MTL;

const Window = @import("../Window.zig");

device: *MTL.Device,
command_queue: *MTL.CommandQueue,

pub fn init(gpa: std.mem.Allocator, window: *Window) Metal {
    _ = gpa;

    const metal_layer: *CA.MetalLayer = .new();

    const device: *MTL.Device = try .new();
    metal_layer.setDevice(device);

    const command_queue = try device.newCommandQueue();

    window.inner.view.setWantsLayer(true);
    window.inner.view.setLayer(metal_layer.toLayer());

    // const vertex_buffer = try device.newBufferWithBytes(
    //     @ptrCast(&vertices),
    //     @sizeOf(@TypeOf(vertices)),
    //     .storage_mode_managed,
    // );
    // defer vertex_buffer.release();

    // const index_buffer = try device.newBufferWithBytes(
    //     @ptrCast(&indices),
    //     @sizeOf(@TypeOf(indices)),
    //     .storage_mode_managed,
    // );
    // defer index_buffer.release();

    return .{
        .device = device,
        .command_queue = command_queue,
    };
}

pub fn deinit(self: *Metal) void {
    self.* = undefined;
}

pub const RenderPipeline = *MTL.RenderPipeline;

pub fn createShaders(m: *Metal, s: []const u8) RenderPipeline {
    const library = try m.device.newLibraryWithSourceSlice(s, null);

    const vertex = try library.newFunctionWithNameSlice("vertex_main");
    const fragment = try library.newFunctionWithNameSlice("fragment_main");

    const pipeline_descriptor: *MTL.RenderPipelineDescriptor = .new();

    pipeline_descriptor.setVertexFunction(vertex);
    pipeline_descriptor.setFragmentFunction(fragment);

    const color_attachment = pipeline_descriptor
        .colorAttachments()
        .objectAtIndexedSubscript(0);

    color_attachment.setPixelFormat(.bgra8Unorm);

    return m.device.newRenderPipelineState(pipeline_descriptor);
}
