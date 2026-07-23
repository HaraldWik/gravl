const PhysicalDevice = @This();

const std = @import("std");
const vk = @import("vulkan");

const Instance = @import("Instance.zig");
const Surface = @import("Surface.zig");

handle: vk.PhysicalDevice,
properties: vk.PhysicalDeviceProperties,
graphics_queue_family_index: u32,

pub const PickError =
    vk.InstanceWrapper.EnumeratePhysicalDevicesAllocError ||
    vk.InstanceWrapper.GetPhysicalDeviceSurfaceSupportKHRError ||
    std.mem.Allocator.Error ||
    error{ NoDevices, MissingSuitableDevice };

pub fn pick(gpa: std.mem.Allocator, instance: Instance, surface: Surface) PickError!PhysicalDevice {
    const physical_devices = try instance.proxy.enumeratePhysicalDevicesAlloc(gpa);
    defer gpa.free(physical_devices);

    if (physical_devices.len == 0)
        return error.NoDevices;

    var best: ?PhysicalDevice = null;
    var best_score: i32 = -1;

    for (physical_devices) |physical_device| {
        const properties = instance.proxy.getPhysicalDeviceProperties(physical_device);

        const families = try instance.proxy.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, gpa);
        defer gpa.free(families);

        var graphics_queue_family_index: ?u32 = null;

        for (families, 0..) |family, i| {
            const index: u32 = @intCast(i);

            const supports_graphics = family.queue_flags.graphics_bit;
            const supports_present = (try instance.proxy.getPhysicalDeviceSurfaceSupportKHR(physical_device, index, surface.handle)) == .true;

            if (supports_graphics and supports_present) {
                graphics_queue_family_index = index;
                break;
            }
        }

        const queue_family = graphics_queue_family_index orelse continue;

        const score: i32 = switch (properties.device_type) {
            .discrete_gpu => 1000,
            .integrated_gpu => 100,
            .virtual_gpu => 67,
            .cpu => 10,
            else => 0,
        };

        const total_score = score + @as(i32, @intCast(properties.limits.max_image_dimension_2d / 1024));

        if (total_score > best_score) {
            best_score = total_score;
            best = .{
                .handle = physical_device,
                .properties = properties,
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
