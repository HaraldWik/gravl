const Image = @This();

const std = @import("std");
const vk = @import("vulkan");

const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

handle: vk.Image,
memory: vk.DeviceMemory,
view: vk.ImageView,

format: vk.Format,
size: vk.Extent2D,

pub const Options = struct {
    usage: vk.ImageUsageFlags = .{ .color_attachment_bit = true },
    aspect: vk.ImageAspectFlags = .{ .color_bit = true },
};

pub fn init(
    gpa: std.mem.Allocator,
    device: Device,
    physical_device: PhysicalDevice,
    format: vk.Format,
    size: vk.Extent2D,
    options: Options,
) !Image {
    const extent = vk.Extent3D{
        .width = size.width,
        .height = size.height,
        .depth = 1,
    };

    const image_info = vk.ImageCreateInfo{
        .image_type = .@"2d",
        .format = format,
        .extent = extent,
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = options.usage,
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };

    const image = try device.proxy.createImage(
        &image_info,
        @ptrCast(@alignCast(gpa.ptr)),
    );
    errdefer device.proxy.destroyImage(
        image,
        @ptrCast(@alignCast(gpa.ptr)),
    );

    const requirements = device.proxy.getImageMemoryRequirements(image);

    const memory_type = PhysicalDevice.findMemoryType(
        requirements.memory_type_bits,
        .{ .device_local_bit = true },
        physical_device.memory_properties,
    );

    const memory_info = vk.MemoryAllocateInfo{
        .allocation_size = requirements.size,
        .memory_type_index = memory_type,
    };

    const memory = try device.proxy.allocateMemory(
        &memory_info,
        @ptrCast(@alignCast(gpa.ptr)),
    );
    errdefer device.proxy.freeMemory(
        memory,
        @ptrCast(@alignCast(gpa.ptr)),
    );

    try device.proxy.bindImageMemory(image, memory, 0);

    const view_info = vk.ImageViewCreateInfo{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .subresource_range = .{
            .aspect_mask = options.aspect,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
    };

    const view = try device.proxy.createImageView(
        &view_info,
        @ptrCast(@alignCast(gpa.ptr)),
    );
    errdefer device.proxy.destroyImageView(
        view,
        @ptrCast(@alignCast(gpa.ptr)),
    );

    return .{
        .handle = image,
        .memory = memory,
        .view = view,
        .format = format,
        .size = size,
    };
}

pub fn deinit(self: Image, gpa: std.mem.Allocator, device: Device) void {
    device.proxy.destroyImageView(self.view, @ptrCast(@alignCast(gpa.ptr)));
    device.proxy.destroyImage(self.handle, @ptrCast(@alignCast(gpa.ptr)));
    device.proxy.freeMemory(self.memory, @ptrCast(@alignCast(gpa.ptr)));
}
