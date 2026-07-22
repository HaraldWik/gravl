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
// swapchain: vk.SwapchainKHR,

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
    const device: Device = try .init(gpa, instance, physical_device, &.{});

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
    };
}

pub fn deinit(self: *Renderer) void {
    const gpa = self.gpa;
    const instance = self.instance;
    self.device.deinit(gpa);
    self.surface.deinit(gpa, instance);
    self.debug_messenger.deinit(gpa, instance);
    instance.deinit(gpa);
    self.gpa_impl.deinit();

    self.dynlib.close();
    self.* = undefined;
}
