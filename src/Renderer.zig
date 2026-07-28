const Renderer = @This();

const builtin = @import("builtin");

const std = @import("std");
const vk = @import("vulkan");

const DynLib = @import("DynLib.zig");
const Window = @import("Window.zig");

const Allocator = @import("Renderer/Allocator.zig");
const Instance = @import("Renderer/Instance.zig");
const DebugMessenger = @import("Renderer/DebugMessenger.zig");
const Surface = @import("Renderer/Surface.zig");
const PhysicalDevice = @import("Renderer/PhysicalDevice.zig");
const Device = @import("Renderer/Device.zig");
const Swapchain = @import("Renderer/Swapchain.zig");
const CommandHandler = @import("Renderer/CommandHandler.zig");
const Buffer = @import("Renderer/Buffer.zig");

pub const Pipeline = @import("Renderer/Pipeline.zig");
pub const ShaderObject = @import("Renderer/ShaderObject.zig");

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
    .linux, .freebsd, .netbsd, .openbsd => "libvulkan.so.1",
    .macos => "libvulkan.1.dylib",
    else => @compileError("unsupported platform"),
};

const debug_instance_extensions: []const [*:0]const u8 = if (builtin.mode == .Debug)
    &.{"VK_EXT_debug_utils"}
else
    &.{};

pub fn init(allocator: std.mem.Allocator, window: *Window) !Renderer {
    const layers: []const [*:0]const u8 = if (builtin.mode == .Debug) &.{
        "VK_LAYER_KHRONOS_validation",
    } else &.{};

    const platform_extensions: []const [*:0]const u8 = switch (builtin.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd => switch (window.inner) {
            .wayland => &.{
                "VK_KHR_surface",
                "VK_KHR_display",
                "VK_KHR_wayland_surface",
            },
            .x11 => &.{
                "VK_KHR_surface",
                "VK_KHR_display",
                "VK_KHR_xlib_surface",
                "VK_KHR_xcb_surface",
            },
        },
        .windows => &.{
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
        },
        .macos => &.{
            "VK_KHR_surface",
            "VK_MVK_macos_surface",
        },
        else => &.{},
    };

    const device_extensions: []const [*:0]const u8 = &.{
        vk.extensions.khr_swapchain.name,
        vk.extensions.ext_shader_object.name,
    };

    const gpa_impl = try Allocator.init(allocator);
    const gpa = gpa_impl.allocator();

    var extensions: std.ArrayList([*:0]const u8) = try .initCapacity(gpa, debug_instance_extensions.len + 4);
    defer extensions.deinit(gpa);
    extensions.appendSliceAssumeCapacity(debug_instance_extensions);
    extensions.appendSliceAssumeCapacity(platform_extensions);

    var dynlib: DynLib = try .open(libvulkan);
    const getInstanceProcAddr = dynlib.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse return error.DynlibLookup;

    const vkb: vk.BaseWrapper = .load(getInstanceProcAddr);

    const instance: Instance = try .init(gpa, vkb, layers, extensions.items);
    const debug_messenger: DebugMessenger = try .init(gpa, instance);
    const surface: Surface = try .init(gpa, instance, window);
    const physical_device: PhysicalDevice = try .pick(gpa, instance, surface);
    std.log.info("poll", .{});
    const device: Device = try .init(gpa, instance, physical_device, device_extensions);
    var swapchain: Swapchain = undefined;
    try swapchain.create(gpa, instance, surface, physical_device, device, window.size);
    const command_handler: CommandHandler = try .init(gpa, physical_device, device);

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

pub fn deinit(self: *Renderer) void {
    const gpa = self.gpa;
    const instance = self.instance;
    const device = self.device;

    device.proxy.deviceWaitIdle() catch unreachable;

    self.command_handler.deinit(gpa, device);
    self.swapchain.deinit(gpa, device);
    device.deinit(gpa);
    self.surface.deinit(gpa, instance);
    self.debug_messenger.deinit(gpa, instance);
    instance.deinit(gpa);
    self.gpa_impl.deinit();

    self.dynlib.close();
    self.* = undefined;
}

fn getFrame(self: Renderer) CommandHandler.FrameData {
    return self.command_handler.frames[self.command_handler.frame_index % CommandHandler.frames_in_flight];
}

pub fn acquire(self: *Renderer, size: Window.Size) !void {
    const device = self.device;
    const swapchain = &self.*.swapchain;
    const frame = self.getFrame();

    _ = try device.proxy.waitForFences(&.{frame.in_flight_fence}, .true, std.math.maxInt(u64));
    try device.proxy.resetFences(&.{frame.in_flight_fence});

    swapchain.drain(self.gpa, device, self.command_handler.frame_index);

    const result = device.wrapper.dispatch.vkAcquireNextImageKHR.?(
        device.handle,
        swapchain.handle,
        std.math.maxInt(u64),
        frame.image_available,
        .null_handle,
        &swapchain.image_index,
    );
    if (result == .error_out_of_date_khr) try self.resize(size);

    try device.proxy.resetCommandBuffer(frame.command_buffer, .{});

    try self.command_handler.begin(self.device, swapchain.*);
}

pub fn submit(self: *Renderer, size: Window.Size) !void {
    const device = self.device;
    const swapchain = self.swapchain;
    const frame = self.getFrame();

    try self.command_handler.end(device, swapchain);

    const wait_semaphores: []const vk.Semaphore = &.{
        frame.image_available,
    };

    const signal_semaphores: []const vk.Semaphore = &.{
        swapchain.finished[swapchain.image_index],
    };

    const wait_stages: []const vk.PipelineStageFlags = &.{
        .{ .color_attachment_output_bit = true },
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

    try device.proxy.queueSubmit(device.graphics_queue, &.{submit_info}, frame.in_flight_fence);

    const present_info: vk.PresentInfoKHR = .{
        .wait_semaphore_count = @intCast(signal_semaphores.len),
        .p_wait_semaphores = signal_semaphores.ptr,
        .swapchain_count = 1,
        .p_swapchains = &.{swapchain.handle},
        .p_image_indices = &.{swapchain.image_index},
    };

    _ = device.proxy.queuePresentKHR(device.graphics_queue, &present_info) catch |err| switch (err) {
        error.OutOfDateKHR => try self.resize(size),
        else => return err,
    };

    self.command_handler.frame_index += 1;
}

pub fn resize(self: *Renderer, size: Window.Size) !void {
    if (size.width == 0 or size.height == 0) return;
    if (size.width == self.swapchain.extent.width and size.height == self.swapchain.extent.height) return;

    try self.swapchain.recreate(
        self.gpa,
        self.instance,
        self.surface,
        self.physical_device,
        self.device,
        size,
        self.command_handler.frame_index,
    );
}

pub fn bindPipeline(self: Renderer, pipeline: Pipeline) void {
    const device = self.device;
    const frame = self.getFrame();
    device.proxy.cmdBindPipeline(frame.command_buffer, .graphics, pipeline.handle);
}

// pub const ShaderBinding = struct {
//     vertex: ShaderObject = .{ .handle = .null_handle, .stage = .vertex },
//     tessellation_control: ShaderObject = .{ .handle = .null_handle, .stage = .tessellation_control },
//     tessellation_evaluation: ShaderObject = .{ .handle = .null_handle, .stage = .tessellation_evaluation },
//     geometry: ShaderObject = .{ .handle = .null_handle, .stage = .geometry },
//     fragment: ShaderObject = .{ .handle = .null_handle, .stage = .fragment },
// };

pub fn bindShader(self: Renderer, shader_object: ShaderObject) void {
    // const shader_count = std.meta.fields(ShaderBinding).len;

    // var handles: [shader_count]vk.ShaderEXT = undefined;
    // var stages: [shader_count]ShaderObject.Stage = undefined;

    // inline for (std.meta.fields(ShaderBinding), 0..) |field, i| {
    //     const shader: ShaderObject = @field(shader_binding, field.name);
    //     handles[i] = shader.handle;
    //     stages[i] = if (shader.handle != .null_handle) shader.stage else ShaderObject.Stage.none;
    // }

    const device = self.device;
    const frame = self.getFrame();
    device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{@bitCast(@intFromEnum(shader_object.stage))}, &.{shader_object.handle});
    // viewport
    device.proxy.cmdSetViewportWithCount(
        frame.command_buffer,
        &.{.{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swapchain.extent.width),
            .height = @floatFromInt(self.swapchain.extent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        }},
    );

    // scissor
    device.proxy.cmdSetScissorWithCount(
        frame.command_buffer,
        &.{.{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.extent,
        }},
    );

    // input assembly
    device.proxy.cmdSetPrimitiveTopology(
        frame.command_buffer,
        .triangle_list,
    );

    device.proxy.cmdSetPrimitiveRestartEnable(
        frame.command_buffer,
        .false,
    );

    // vertex input (empty)
    device.proxy.cmdSetVertexInputEXT(
        frame.command_buffer,
        null,
        null,
    );

    // rasterizer
    device.proxy.cmdSetRasterizerDiscardEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetPolygonModeEXT(
        frame.command_buffer,
        .fill,
    );

    device.proxy.cmdSetCullMode(
        frame.command_buffer,
        .{},
    );

    device.proxy.cmdSetFrontFace(
        frame.command_buffer,
        .counter_clockwise,
    );

    device.proxy.cmdSetDepthBiasEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetDepthClampEnableEXT(
        frame.command_buffer,
        .false,
    );

    // multisampling
    device.proxy.cmdSetRasterizationSamplesEXT(
        frame.command_buffer,
        .{ .@"1_bit" = true },
    );

    device.proxy.cmdSetSampleMaskEXT(
        frame.command_buffer,
        .{ .@"1_bit" = true },
        &.{0xffffffff},
    );

    device.proxy.cmdSetAlphaToCoverageEnableEXT(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetAlphaToOneEnableEXT(
        frame.command_buffer,
        .false,
    );

    // depth/stencil
    device.proxy.cmdSetDepthTestEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetDepthWriteEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetDepthCompareOp(
        frame.command_buffer,
        .less,
    );

    device.proxy.cmdSetDepthBoundsTestEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetStencilTestEnable(
        frame.command_buffer,
        .false,
    );

    // blending
    device.proxy.cmdSetColorBlendEnableEXT(
        frame.command_buffer,
        0,
        &.{.true},
    );

    device.proxy.cmdSetColorBlendEquationEXT(
        frame.command_buffer,
        0,
        &.{.{
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
        }},
    );

    device.proxy.cmdSetColorWriteMaskEXT(
        frame.command_buffer,
        0,
        &.{.{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true,
        }},
    );

    device.proxy.cmdSetLogicOpEnableEXT(
        frame.command_buffer,
        .false,
    );
}

pub fn draw(self: Renderer) void {
    const device = self.device;
    const frame = self.getFrame();
    device.proxy.cmdDraw(frame.command_buffer, 3, 1, 0, 0);
}
