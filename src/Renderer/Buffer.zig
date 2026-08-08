const Buffer = @This();

const std = @import("std");
const vk = @import("vulkan");

const PhysicalDevice = @import("PhysicalDevice.zig");
const Device = @import("Device.zig");

handle: vk.Buffer,
memory: vk.DeviceMemory,
usage: Usage,

pub const Usage = enum(vk.Flags) {
    uniform = 0x00000010,
    storage = 0x00000020,
    index = 0x00000040,
    vertex = 0x00000080,
    indirect = 0x00000100,
};

pub fn init(comptime T: type, gpa: std.mem.Allocator, physical_device: PhysicalDevice, device: Device, usage: Usage, data: []const T) !Buffer {
    const create_info: *const vk.BufferCreateInfo = &.{
        .size = data.len * @sizeOf(T),
        .usage = @bitCast(@intFromEnum(usage)),
        .sharing_mode = .exclusive,
    };

    const handle = try device.proxy.createBuffer(create_info, @ptrCast(@alignCast(gpa.ptr)));

    const requirements = device.proxy.getBufferMemoryRequirements(handle);

    const memory_type = PhysicalDevice.findMemoryType(
        requirements.memory_type_bits,
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        physical_device.memory_properties,
    );

    const memory_allocate_info: *const vk.MemoryAllocateInfo = &.{
        .allocation_size = requirements.size,
        .memory_type_index = memory_type,
    };

    const memory = try device.proxy.allocateMemory(memory_allocate_info, @ptrCast(@alignCast(gpa.ptr)));

    try device.proxy.bindBufferMemory(handle, memory, 0);

    const mapped = try device.proxy.mapMemory(memory, 0, create_info.size, .{});

    const dst: [*]T = @ptrCast(@alignCast(mapped));
    @memcpy(dst[0..data.len], data);

    device.proxy.unmapMemory(memory);

    return .{
        .handle = handle,
        .memory = memory,
        .usage = usage,
    };
}

pub fn deinit(self: Buffer, gpa: std.mem.Allocator, device: Device) void {
    device.proxy.destroyBuffer(self.handle, @ptrCast(@alignCast(gpa.ptr)));
    device.proxy.freeMemory(self.memory, @ptrCast(@alignCast(gpa.ptr)));
}

pub fn getAddress(self: Buffer, device: Device) vk.DeviceAddress {
    return device.proxy.getBufferDeviceAddress(&.{ .buffer = self.handle });
}
