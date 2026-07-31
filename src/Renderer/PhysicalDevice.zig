const PhysicalDevice = @This();

const std = @import("std");
const vk = @import("vulkan");

const Instance = @import("Instance.zig");
const Surface = @import("Surface.zig");

handle: vk.PhysicalDevice,
properties: vk.PhysicalDeviceProperties,
memory_properties: vk.PhysicalDeviceMemoryProperties,
graphics_queue_family_index: u32,

pub const PickError =
    vk.InstanceWrapper.EnumeratePhysicalDevicesAllocError ||
    vk.InstanceWrapper.GetPhysicalDeviceSurfaceSupportKHRError ||
    std.mem.Allocator.Error ||
    error{ NoDevices, MissingSuitableDevice };

pub fn pick(gpa: std.mem.Allocator, instance: Instance, surface: Surface) PickError!PhysicalDevice {
    const physical_devices = try instance.proxy.enumeratePhysicalDevicesAlloc(gpa);
    defer gpa.free(physical_devices);

    if (physical_devices.len == 0) return error.NoDevices;

    var best: ?PhysicalDevice = null;
    var best_score: i32 = -1;

    for (physical_devices) |physical_device| {
        const properties = instance.proxy.getPhysicalDeviceProperties(physical_device);
        const memory_properties = instance.proxy.getPhysicalDeviceMemoryProperties(physical_device);

        const families = try instance.proxy.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, gpa);
        defer gpa.free(families);

        const queue_family = for (families, 0..) |family, i| {
            const index: u32 = @truncate(i);

            const graphics_support = family.queue_flags.graphics_bit;
            const surface_support = try instance.proxy.getPhysicalDeviceSurfaceSupportKHR(physical_device, index, surface.handle) == .true;

            if (graphics_support and surface_support) break index;
        } else continue;

        var score: i32 = switch (properties.device_type) {
            .discrete_gpu => 1000,
            .integrated_gpu => 100,
            .virtual_gpu => 67,
            .cpu => 10,
            else => 0,
        };

        score += @as(i32, @intCast(properties.limits.max_image_dimension_2d / 1024));

        if (score > best_score) {
            best_score = score;
            best = .{
                .handle = physical_device,
                .properties = properties,
                .memory_properties = memory_properties,
                .graphics_queue_family_index = queue_family,
            };
        }
    }

    if (best) |physical_device| {
        std.log.info("selected ({t}) {s}", .{ physical_device.properties.device_type, physical_device.properties.device_name });
        return physical_device;
    }

    return error.MissingSuitableDevice;
}
