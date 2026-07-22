const Device = @This();

const std = @import("std");
const vk = @import("vulkan");

const Instance = @import("Instance.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

handle: vk.Device,
wrapper: *vk.DeviceWrapper,
proxy: vk.DeviceProxy,
graphics_queue: vk.Queue,
command_pool: vk.CommandPool,
immidiate_fence: vk.Fence,

pub fn init(gpa: std.mem.Allocator, instance: Instance, physical_device: PhysicalDevice, extensions: []const [*:0]const u8) !Device {
    const properties = try instance.proxy.enumerateDeviceExtensionPropertiesAlloc(physical_device.handle, null, gpa);
    defer gpa.free(properties);

    for (extensions) |extension| for (properties) |property| {
        const name: []const u8 = std.mem.sliceTo(&property.extension_name, 0);
        if (!std.mem.eql(u8, std.mem.span(extension), name)) return error.MissingDeviceExtension;
    };

    const features = instance.proxy.getPhysicalDeviceFeatures(physical_device.handle);

    var queue_priority: f32 = 1.0;
    const queue_info: vk.DeviceQueueCreateInfo = .{
        .queue_family_index = physical_device.graphics_queue_family_index,
        .queue_count = 1,
        .p_queue_priorities = @ptrCast(&queue_priority),
    };

    var dynamic_rendering_features: vk.PhysicalDeviceDynamicRenderingFeatures = .{
        .dynamic_rendering = .true,
    };

    var sync2_features: vk.PhysicalDeviceSynchronization2Features = .{
        .p_next = &dynamic_rendering_features,
        .synchronization_2 = .true,
    };

    var shader_obj_features: vk.PhysicalDeviceShaderObjectFeaturesEXT = .{
        .p_next = &sync2_features,
        .shader_object = .true,
    };

    var buffer_device_address_features: vk.PhysicalDeviceBufferDeviceAddressFeatures = .{
        .p_next = &shader_obj_features,
        .buffer_device_address = .true,
    };

    var descriptor_buffer_features: vk.PhysicalDeviceDescriptorBufferFeaturesEXT = .{
        .p_next = &buffer_device_address_features,
        .descriptor_buffer = .true,
        .descriptor_buffer_push_descriptors = .true,
    };
    var inline_uniform_block_features: vk.PhysicalDeviceInlineUniformBlockFeatures = .{
        .p_next = &descriptor_buffer_features,
        .inline_uniform_block = .true,
    };

    var descriptor_indexing_feature: vk.PhysicalDeviceDescriptorIndexingFeatures = .{
        .p_next = &inline_uniform_block_features,
        .shader_sampled_image_array_non_uniform_indexing = .true,
    };

    const create_info: *const vk.DeviceCreateInfo = &.{
        .p_next = &descriptor_indexing_feature,
        .queue_create_info_count = 1,
        .p_queue_create_infos = @ptrCast(&queue_info),
        .p_enabled_features = &features,
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
    };

    const handle = try instance.proxy.createDevice(physical_device.handle, create_info, @ptrCast(@alignCast(gpa.ptr)));

    const wrapper = try gpa.create(vk.DeviceWrapper);
    errdefer gpa.destroy(wrapper);

    wrapper.* = .load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    const proxy: vk.DeviceProxy = .init(handle, wrapper);

    const graphics_queue = proxy.getDeviceQueue(physical_device.graphics_queue_family_index, 0);

    const command_pool_create_info: *const vk.CommandPoolCreateInfo = &.{
        .queue_family_index = physical_device.graphics_queue_family_index,
    };
    const command_pool = try proxy.createCommandPool(command_pool_create_info, @ptrCast(@alignCast(gpa.ptr)));

    const fence_create_info: *const vk.FenceCreateInfo = &.{
        .flags = .{ .signaled_bit = true },
    };
    const fence = try proxy.createFence(fence_create_info, @ptrCast(@alignCast(gpa.ptr)));

    return .{
        .handle = handle,
        .wrapper = wrapper,
        .proxy = proxy,
        .graphics_queue = graphics_queue,
        .command_pool = command_pool,
        .immidiate_fence = fence,
    };
}

pub fn deinit(self: Device, gpa: std.mem.Allocator) void {
    self.proxy.destroyFence(self.immidiate_fence, @ptrCast(@alignCast(gpa.ptr)));
    self.proxy.destroyCommandPool(self.command_pool, @ptrCast(@alignCast(gpa.ptr)));
    self.proxy.destroyDevice(@ptrCast(@alignCast(gpa.ptr)));
    gpa.destroy(self.wrapper);
}
