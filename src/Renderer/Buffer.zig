const Buffer = @This();

const std = @import("std");
const vk = @import("vulkan");

const Device = @import("Device.zig");

handle: vk.Buffer,

pub const Usage = enum(vk.Flags) {
    uniform = 0x00000010,
    storage = 0x00000020,
    index = 0x00000040,
    vertex = 0x00000080,
    indirect = 0x00000100,
};

pub fn init(comptime T: type, gpa: std.mem.Allocator, device: Device, usage: Usage, data: []const T) Buffer {
    // vk.BufferUsageFlags == .transfer_src_bit;

    const create_info: *const vk.BufferCreateInfo = &.{
        .size = data.len * @sizeOf(T),
        .usage = @bitCast(usage),
        .sharing_mode = .exclusive,
    };

    const handle = try device.proxy.createBuffer(create_info, @ptrCast(@alignCast(gpa.ptr)));

    //     const requirements = device.proxy.getBufferMemoryRequirements(handle);

    //     const memory_index = findMemoryType(
    //     physical_device.memory_properties,
    //     requirements.memory_type_bits,
    //     .{
    //         .host_visible_bit = true,
    //         .host_coherent_bit = true,
    //     },

    //     const alloc_info: vk.MemoryAllocateInfo = .{
    //     .allocation_size = requirements.size,
    //     .memory_type_index = memory_index,
    // };

    // const memory = try device.allocateMemory(&alloc_info, allocator);
    // );

    return .{ .handle = handle };
}

pub fn deinit(self: Buffer, gpa: std.mem.Allocator, device: Device) void {
    device.proxy.destroyBuffer(self.handle, @ptrCast(@alignCast(gpa.ptr)));
}
