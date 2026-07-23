const CommandHandler = @This();

const std = @import("std");
const vk = @import("vulkan");

const Instance = @import("Instance.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Device = @import("Device.zig");
const Swapchain = @import("Swapchain.zig");

command_pool: vk.CommandPool,

frames: [frames_in_flight]FrameData,
frame_index: usize = 0,

pub const frames_in_flight = 3;

pub const FrameData = struct {
    command_buffer: vk.CommandBuffer,
    image_available: vk.Semaphore,
    in_flight_fence: vk.Fence,
};

pub fn init(gpa: std.mem.Allocator, physical_device: PhysicalDevice, device: Device) !CommandHandler {
    const command_pool_create_info: *const vk.CommandPoolCreateInfo = &.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = physical_device.graphics_queue_family_index,
    };
    const command_pool = try device.proxy.createCommandPool(command_pool_create_info, @ptrCast(@alignCast(gpa.ptr)));

    var frames: [frames_in_flight]FrameData = undefined;

    for (&frames) |*frame| {
        const create_info: *const vk.CommandBufferAllocateInfo = &.{
            .command_pool = command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        };
        try device.proxy.allocateCommandBuffers(create_info, @ptrCast(&frame.command_buffer));

        frame.image_available = try device.proxy.createSemaphore(&.{}, @ptrCast(@alignCast(gpa.ptr)));

        const fence_create_info: *const vk.FenceCreateInfo = &.{
            .flags = .{ .signaled_bit = true },
        };
        frame.in_flight_fence = try device.proxy.createFence(fence_create_info, @ptrCast(@alignCast(gpa.ptr)));
    }

    return .{
        .command_pool = command_pool,
        .frames = frames,
    };
}

pub fn deinit(self: CommandHandler, gpa: std.mem.Allocator, device: Device) void {
    for (&self.frames) |*frame| {
        device.proxy.destroySemaphore(frame.image_available, @ptrCast(@alignCast(gpa.ptr)));
        device.proxy.destroyFence(frame.in_flight_fence, @ptrCast(@alignCast(gpa.ptr)));
    }
    device.proxy.destroyCommandPool(self.command_pool, @ptrCast(@alignCast(gpa.ptr)));
}

pub fn begin(self: *CommandHandler, device: Device, swapchain: Swapchain) !void {
    const frame = self.frames[self.frame_index % frames_in_flight];
    const command_buffer = frame.command_buffer;

    const begin_info: *const vk.CommandBufferBeginInfo = &.{};
    try device.proxy.beginCommandBuffer(command_buffer, begin_info);

    const memory_barrier: vk.ImageMemoryBarrier = .{
        .src_access_mask = .{},
        .dst_access_mask = .{ .color_attachment_write_bit = true },
        .old_layout = .undefined,
        .new_layout = .color_attachment_optimal,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = swapchain.images[swapchain.image_index],
        .subresource_range = .{
            .aspect_mask = .{
                .color_bit = true,
            },
            .level_count = 1,
            .layer_count = 1,
            .base_mip_level = 0,
            .base_array_layer = 0,
        },
    };
    device.proxy.cmdPipelineBarrier(
        command_buffer,
        .{ .top_of_pipe_bit = true },
        .{ .color_attachment_output_bit = true },
        .{},
        null,
        null,
        &.{memory_barrier},
    );

    const viewport: vk.Viewport = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };
    device.proxy.cmdSetViewport(command_buffer, 0, &.{viewport});

    const scissor: vk.Rect2D = .{
        .extent = swapchain.extent,
        .offset = .{ .x = 0, .y = 0 },
    };
    device.proxy.cmdSetScissor(command_buffer, 0, &.{scissor});

    const clear_color: vk.ClearValue = .{
        .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } },
    };
    const color_attachment_infos: []const vk.RenderingAttachmentInfo = &.{
        .{
            .image_view = swapchain.image_views[swapchain.image_index],
            .image_layout = .attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = clear_color,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
        },
    };

    const rendering_info: *const vk.RenderingInfo = &.{
        .layer_count = 1,
        .color_attachment_count = @intCast(color_attachment_infos.len),
        .p_color_attachments = color_attachment_infos.ptr,
        .render_area = .{
            .extent = swapchain.extent,
            .offset = .{ .x = 0, .y = 0 },
        },
        .view_mask = 0,
    };

    device.proxy.cmdBeginRendering(command_buffer, rendering_info);
}

pub fn end(self: *CommandHandler, device: Device, swapchain: Swapchain) !void {
    const frame = self.frames[self.frame_index % frames_in_flight];
    const command_buffer = frame.command_buffer;

    device.proxy.cmdEndRendering(command_buffer);

    const end_memory_barrier: vk.ImageMemoryBarrier = .{
        .src_access_mask = .{ .color_attachment_write_bit = true },
        .dst_access_mask = .{},
        .old_layout = .color_attachment_optimal,
        .new_layout = .present_src_khr,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = swapchain.images[swapchain.image_index],
        .subresource_range = .{
            .aspect_mask = .{
                .color_bit = true,
            },
            .level_count = 1,
            .layer_count = 1,
            .base_mip_level = 0,
            .base_array_layer = 0,
        },
    };
    device.proxy.cmdPipelineBarrier(
        command_buffer,
        .{ .color_attachment_output_bit = true },
        .{ .bottom_of_pipe_bit = true },
        .{},
        null,
        null,
        &.{end_memory_barrier},
    );
    try device.proxy.endCommandBuffer(command_buffer);
}
