const Vulkan = @This();

const builtin = @import("builtin");

const std = @import("std");
const vk = @import("vulkan");

const DynLib = @import("../DynLib.zig");
const Window = @import("../Window.zig");

const Renderer = @import("../Renderer.zig");

const Allocator = @import("Vulkan/Allocator.zig");
const Instance = @import("Vulkan/Instance.zig");
const DebugMessenger = @import("Vulkan/DebugMessenger.zig");
const Surface = @import("Vulkan/Surface.zig");
const PhysicalDevice = @import("Vulkan/PhysicalDevice.zig");
const Device = @import("Vulkan/Device.zig");
const Swapchain = @import("Vulkan/Swapchain.zig");
const CommandHandler = @import("Vulkan/CommandHandler.zig");
const ShaderObject = @import("Vulkan/ShaderObject.zig");
const Buffer = @import("Vulkan/Buffer.zig");
const Image = @import("Vulkan/Image.zig");

gpa_impl: *Allocator,
gpa: std.mem.Allocator,

dynlib: DynLib,

vkb: vk.BaseWrapper,
instance: Instance,
debug_messenger: DebugMessenger,
surface: Surface,
physical_device: PhysicalDevice,
device: Device,
// vma: Vma,
swapchain: Swapchain,
command_handler: CommandHandler,

const libvulkan = switch (builtin.os.tag) {
    .windows => "vulkan-1.dll",
    .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => "libvulkan.so.1",
    .macos => "libvulkan.1.dylib",
    else => @compileError("unsupported platform"),
};

const debug_instance_extensions: []const [*:0]const u8 = if (builtin.mode == .debug)
    &.{"VK_EXT_debug_utils"}
else
    &.{};

const layers: []const [*:0]const u8 = if (builtin.mode == .debug)
    &.{"VK_LAYER_KHRONOS_validation"}
else
    &.{};

pub fn init(allocator: std.mem.Allocator, window: *Window) !Vulkan {
    const platform_extensions: []const [*:0]const u8 = switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => switch (window.inner) {
            .wayland => &.{
                vk.extensions.khr_surface.name,
                vk.extensions.khr_wayland_surface.name,
            },
            .x11 => &.{
                vk.extensions.khr_surface.name,
                vk.extensions.khr_xlib_surface.name,
            },
        },
        .windows => &.{
            vk.extensions.khr_surface.name,
            vk.extensions.khr_win_32_surface.name,
        },
        .macos => &.{
            vk.extensions.khr_surface.name,
            vk.extensions.ext_metal_surface.name,
        },
        else => &.{},
    };

    const device_extensions: []const [*:0]const u8 = &.{
        vk.extensions.khr_swapchain.name,
        vk.extensions.ext_shader_object.name,
    };

    const gpa_impl = try Allocator.init(allocator);
    errdefer allocator.destroy(gpa_impl);
    const gpa = gpa_impl.allocator();

    var extensions: std.ArrayList([*:0]const u8) = try .initCapacity(gpa, debug_instance_extensions.len + 4);
    defer extensions.deinit(gpa);
    extensions.appendSliceAssumeCapacity(debug_instance_extensions);
    extensions.appendSliceAssumeCapacity(platform_extensions);

    var dynlib: DynLib = try .open(libvulkan);
    const getInstanceProcAddr = dynlib.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse return error.DynlibLookup;

    const vkb: vk.BaseWrapper = .load(getInstanceProcAddr);

    const instance: Instance = try .init(gpa, vkb, layers, extensions.items);
    errdefer instance.deinit(gpa);

    const debug_messenger: DebugMessenger = try .init(gpa, instance);
    errdefer debug_messenger.deinit(gpa, instance);

    const surface: Surface = try .init(gpa, instance, window);
    errdefer surface.deinit(gpa, instance);

    const physical_device: PhysicalDevice = try .pick(gpa, instance, surface);
    const device: Device = try .init(gpa, instance, physical_device, device_extensions);
    errdefer device.deinit(gpa);

    var swapchain: Swapchain = undefined;
    try swapchain.create(gpa, instance, surface, physical_device, device, window.size);
    errdefer swapchain.deinit(gpa, device);

    const command_handler: CommandHandler = try .init(gpa, physical_device, device);
    errdefer command_handler.deinit(gpa, device);

    return .{
        .gpa_impl = gpa_impl,
        .gpa = gpa,

        .dynlib = dynlib,

        .vkb = vkb,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .command_handler = command_handler,
    };
}

pub fn deinit(v: *Vulkan) void {
    const gpa = v.gpa;

    v.device.proxy.deviceWaitIdle() catch unreachable;

    v.command_handler.deinit(gpa, v.device);
    v.swapchain.deinit(gpa, v.device);
    v.device.deinit(gpa);
    v.surface.deinit(gpa, v.instance);
    v.debug_messenger.deinit(gpa, v.instance);
    v.instance.deinit(gpa);
    v.gpa_impl.deinit();

    v.dynlib.close();
    v.* = undefined;
}

pub fn resize(v: *Vulkan, size: Window.Size) !void {
    if (size.width == 0 or size.height == 0) return;
    if (size.width == v.swapchain.extent.width and size.height == v.swapchain.extent.height) return;

    try v.swapchain.recreate(
        v.gpa,
        v.instance,
        v.surface,
        v.physical_device,
        v.device,
        size,
        v.command_handler.frame_index,
    );
}

pub const Frame = struct {
    renderer: *Vulkan,
    image: vk.Image,
    command_buffer: vk.CommandBuffer,

    pub fn begin(v: *Vulkan, options: Renderer.Frame.BeginOptions) !Frame {
        try v.resize(options.size);

        const frame = v.command_handler.frames[v.command_handler.frame_index % CommandHandler.frames_in_flight];

        _ = try v.device.proxy.waitForFences(
            &.{frame.in_flight_fence},
            .true,
            std.math.maxInt(u64),
        );

        try v.device.proxy.resetFences(&.{frame.in_flight_fence});

        v.swapchain.drain(
            v.gpa,
            v.device,
            v.command_handler.frame_index,
        );

        const result = v.device.wrapper.dispatch.vkAcquireNextImageKHR.?(
            v.device.handle,
            v.swapchain.handle,
            std.math.maxInt(u64),
            frame.image_available,
            .null_handle,
            &v.swapchain.image_index,
        );

        if (result == .error_out_of_date_khr or result == .suboptimal_khr) {
            try v.resize(options.size); // TODO window size
            return error.SwapchainOutOfDate;
        }

        const image = v.swapchain.images[v.swapchain.image_index];

        // var barrier: vk.ImageMemoryBarrier2 = .{
        //     .srcStageMask = .{ .top_of_pipe = true },
        //     .srcAccessMask = .{},
        //     .dstStageMask = .{ .color_attachment_output = true },
        //     .dstAccessMask = .{ .color_attachment_write = true },
        //     .oldLayout = .undefined,
        //     .newLayout = .color_attachment_optimal,
        //     .image = image,
        //     .subresourceRange = .{
        //         .aspectMask = .{ .color = true },
        //         .baseMipLevel = 0,
        //         .levelCount = 1,
        //         .baseArrayLayer = 0,
        //         .layerCount = 1,
        //     },
        // };

        // const dependency: *const vk.DependencyInfo = &.{
        //     .imageMemoryBarrierCount = 1,
        //     .pImageMemoryBarriers = &barrier,
        // };

        // device.proxy.cmdPipelineBarrier2(frame.command_buffer, dependency);

        try v.device.proxy.resetCommandBuffer(
            frame.command_buffer,
            .{},
        );

        try v.device.proxy.beginCommandBuffer(
            frame.command_buffer,
            &.{},
        );

        const color_barrier = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{
                .color_attachment_write = true,
            },
            .old_layout = .undefined,
            .new_layout = .color_attachment_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = .{
                .aspect_mask = .{
                    .color = true,
                },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        v.device.proxy.cmdPipelineBarrier(
            frame.command_buffer,
            .{ .top_of_pipe = true },
            .{ .color_attachment_output = true },
            .{},
            null,
            null,
            &.{color_barrier},
        );

        v.device.proxy.cmdSetViewportWithCount(
            frame.command_buffer,
            &.{.{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(v.swapchain.extent.width),
                .height = @floatFromInt(v.swapchain.extent.height),
                .min_depth = 0,
                .max_depth = 1,
            }},
        );

        v.device.proxy.cmdSetScissorWithCount(
            frame.command_buffer,
            &.{.{
                .offset = .{ .x = 0, .y = 0 },
                .extent = v.swapchain.extent,
            }},
        );

        const clear_color: vk.ClearValue = .{
            .color = .{
                .float_32 = options.clear_color,
            },
        };

        const clear_depth: vk.ClearValue = .{
            .depth_stencil = .{
                .depth = 1.0,
                .stencil = 0,
            },
        };

        const color_attachment: *const vk.RenderingAttachmentInfo = &.{
            .image_view = v.swapchain.image_views[v.swapchain.image_index],
            .image_layout = .color_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = clear_color,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
        };

        const depth_attachment: *const vk.RenderingAttachmentInfo = &.{
            .image_view = v.swapchain.depth.image_view,
            .image_layout = .depth_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = clear_depth,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
        };

        const rendering_info: *const vk.RenderingInfo = &.{
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = v.swapchain.extent,
            },
            .layer_count = 1,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(color_attachment),
            .p_depth_attachment = depth_attachment,
            .view_mask = 0,
        };

        v.device.proxy.cmdBeginRendering(
            frame.command_buffer,
            rendering_info,
        );

        v.device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .vertex = true }}, null);
        v.device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .tessellation_control = true }}, null);
        v.device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .tessellation_evaluation = true }}, null);
        v.device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .geometry = true }}, null);
        v.device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .fragment = true }}, null);

        return .{
            .renderer = v,
            .image = image,
            .command_buffer = frame.command_buffer,
        };
    }

    pub fn end(frame: Frame) !void {
        const device = frame.renderer.device;
        const swapchain = frame.renderer.swapchain;
        const frame_data = frame.renderer.command_handler.frames[frame.renderer.command_handler.frame_index % CommandHandler.frames_in_flight];

        // submit

        device.proxy.cmdEndRendering(frame.command_buffer);

        const color_to_present: vk.ImageMemoryBarrier = .{
            .src_access_mask = .{ .color_attachment_write = true },
            .dst_access_mask = .{},
            .old_layout = .color_attachment_optimal,
            .new_layout = .present_src_khr,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = frame.image,
            .subresource_range = .{
                .aspect_mask = .{ .color = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        device.proxy.cmdPipelineBarrier(
            frame.command_buffer,
            .{ .color_attachment_output = true },
            .{},
            .{},
            null,
            null,
            &.{color_to_present},
        );

        try device.proxy.endCommandBuffer(frame.command_buffer);

        // present
        const wait_semaphores: []const vk.Semaphore = &.{
            frame_data.image_available,
        };

        const signal_semaphores: []const vk.Semaphore = &.{
            swapchain.finished[swapchain.image_index],
        };

        const wait_stages: []const vk.PipelineStageFlags = &.{
            .{ .color_attachment_output = true },
        };

        const submit_info: vk.SubmitInfo = .{
            .command_buffer_count = 1,
            .p_command_buffers = &.{frame.command_buffer},
            .wait_semaphore_count = @intCast(wait_semaphores.len),
            .p_wait_semaphores = wait_semaphores.ptr,
            .signal_semaphore_count = @intCast(signal_semaphores.len),
            .p_signal_semaphores = signal_semaphores.ptr,
            .p_wait_dst_stage_mask = wait_stages.ptr,
        };

        try device.proxy.queueSubmit(device.graphics_queue, &.{submit_info}, frame_data.in_flight_fence);

        const present_info: vk.PresentInfoKHR = .{
            .wait_semaphore_count = @intCast(signal_semaphores.len),
            .p_wait_semaphores = signal_semaphores.ptr,
            .swapchain_count = 1,
            .p_swapchains = &.{swapchain.handle},
            .p_image_indices = &.{swapchain.image_index},
        };

        _ = device.proxy.queuePresentKHR(device.graphics_queue, &present_info) catch |err| switch (err) {
            error.OutOfDateKHR => {},
            else => return err,
        };

        frame.renderer.command_handler.frame_index += 1;
    }

    pub fn bindPipeline(frame: Frame, pipeline: GraphicsPipeline) void {
        _ = frame;
        _ = pipeline;
    }

    pub fn drawMesh(frame: Frame, mesh: Mesh) void {
        _ = frame;
        _ = mesh;
    }
};

pub const GraphicsPipeline = struct {
    pub fn init(v: *Vulkan, options: Renderer.GraphicsPipeline.CreateOptions) !GraphicsPipeline {
        _ = v;
        _ = options;
        return .{};
    }

    pub fn deinit(pipeline: GraphicsPipeline, v: *Vulkan) void {
        _ = pipeline;
        _ = v;
    }

    pub fn bindPipeline(frame: Frame, pipeline: GraphicsPipeline) void {
        _ = frame;
        _ = pipeline;
    }

    pub fn drawMesh(frame: Frame, mesh: Mesh) void {
        _ = frame;
        _ = mesh;
    }
};

pub const Mesh = struct {
    pub fn init(v: *Vulkan, comptime Vertex: type, vertices: []const Vertex, indices: []const u32) !Mesh {
        _ = v;
        _ = vertices;
        _ = indices;
        return .{};
    }

    pub fn deinit(mesh: Mesh, v: *Vulkan) void {
        _ = mesh;
        _ = v;
    }
};
