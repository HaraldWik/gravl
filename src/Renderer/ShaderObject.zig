const ShaderObject = @This();

const std = @import("std");
const vk = @import("vulkan");

const Device = @import("Device.zig");

handle: vk.ShaderEXT,
stage: Stage,

pub const Stage = enum(vk.Flags) {
    none = 0x00000000,
    vertex = 0x00000001,
    tessellation_control = 0x00000002,
    tessellation_evaluation = 0x00000004,
    geometry = 0x00000008,
    fragment = 0x00000010,
    compute = 0x00000020,
};

pub const Description = struct {
    stage: Stage,
    next_stage: Stage = .none,
    source: []const u8,
    entry_name: [*:0]const u8 = "main",
};

pub fn init(gpa: std.mem.Allocator, device: Device, description: Description) !ShaderObject {
    const magic = std.mem.readInt(u32, @ptrCast(std.mem.bytesAsSlice(u32, description.source[0..4])), .little);
    std.debug.assert(magic == 0x7230203);

    const create_info: *const vk.ShaderCreateInfoEXT = &.{
        .stage = @bitCast(@intFromEnum(description.stage)),
        .next_stage = @bitCast(@intFromEnum(description.next_stage)),
        .code_type = .spirv_ext,
        .code_size = description.source.len,
        .p_code = @ptrCast(description.source.ptr),
        .p_name = description.entry_name,
    };

    var handle: vk.ShaderEXT = undefined;
    _ = try device.proxy.createShadersEXT(&.{create_info.*}, @ptrCast(@alignCast(gpa.ptr)), @ptrCast(&handle));
    return .{
        .handle = handle,
        .stage = description.stage,
    };
}

pub fn initMany(comptime count: usize, gpa: std.mem.Allocator, device: Device, descriptions: [count]Description) ![count]ShaderObject {
    var create_infos: [count]vk.ShaderCreateInfoEXT = undefined;
    for (&create_infos, &descriptions) |*create_info, description| create_info.* = vk.ShaderCreateInfoEXT{
        .code_type = .spirv_ext,
        .stage = @bitCast(@intFromEnum(description.stage)),
        .next_stage = @bitCast(@intFromEnum(description.next_stage)),
        .code_size = description.source.len,
        .p_code = @ptrCast(description.source.ptr),
        .p_name = description.entry_name,
    };

    var handles: [count]vk.ShaderEXT = undefined;
    _ = try device.proxy.createShadersEXT(&create_infos, @ptrCast(@alignCast(gpa.ptr)), &handles);

    var shader_objects: [count]ShaderObject = undefined;
    for (&shader_objects, &handles, &descriptions) |*shader_object, handle, description| shader_object.* = .{
        .handle = handle,
        .stage = description.stage,
    };

    return shader_objects;
}

pub fn deinit(self: ShaderObject, gpa: std.mem.Allocator, device: Device) void {
    device.proxy.destroyShaderEXT(self.handle, @ptrCast(@alignCast(gpa.ptr)));
}
