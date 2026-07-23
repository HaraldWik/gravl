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

pub const Pipeline = @import("Renderer/Pipeline.zig");

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

pub fn acquire(self: *Renderer, size: Window.Size) !void {
    const device = self.device;
    const swapchain = &self.*.swapchain;
    const frame = self.command_handler.frames[self.command_handler.frame_index % CommandHandler.frames_in_flight];

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
    const frame = self.command_handler.frames[self.command_handler.frame_index % CommandHandler.frames_in_flight];

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

pub fn bindPipeline(self: *Renderer, pipeline: Pipeline) void {
    const device = self.device;
    const frame = self.command_handler.frames[self.command_handler.frame_index % CommandHandler.frames_in_flight];
    const command_buffer = frame.command_buffer;

    device.proxy.cmdBindPipeline(command_buffer, .graphics, pipeline.handle);
    device.proxy.cmdDraw(command_buffer, 3, 1, 0, 0);
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
