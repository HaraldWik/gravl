const Instance = @This();

const std = @import("std");
const vk = @import("vulkan");

handle: vk.Instance,
wrapper: *vk.InstanceWrapper,
proxy: vk.InstanceProxy,

pub const InitError = vk.BaseWrapper.CreateInstanceError || vk.BaseWrapper.EnumerateInstanceVersionError || std.mem.Allocator.Error || error{VulkanVersionTooOld};

pub fn init(
    gpa: std.mem.Allocator,
    vkb: vk.BaseWrapper,
    layers: []const [*:0]const u8,
    extensions: []const [*:0]const u8,
) InitError!Instance {
    const api_version = vk.makeApiVersion(0, 1, 4, 0);

    const application_info: *const vk.ApplicationInfo = &.{
        .p_application_name = null,
        .application_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
        .p_engine_name = "real_engine",
        .engine_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
        .api_version = api_version.toU32(),
    };

    const create_info: *const vk.InstanceCreateInfo = &.{
        .p_application_info = application_info,
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
    };

    const available_version: vk.Version = @bitCast(try vkb.enumerateInstanceVersion());

    if (available_version.major < api_version.major or available_version.minor < api_version.minor) {
        std.log.err("required vulkan version {d}.{d} is not available, found {d}.{d}", .{ api_version.major, api_version.minor, available_version.major, available_version.minor });
        return error.VulkanVersionTooOld;
    }

    const handle = vkb.createInstance(create_info, null) catch |err| return switch (err) {
        error.LayerNotPresent => Instance.init(gpa, vkb, &.{}, extensions),
        else => err,
    };

    const wrapper = try gpa.create(vk.InstanceWrapper);
    errdefer gpa.destroy(wrapper);
    wrapper.* = .load(handle, vkb.dispatch.vkGetInstanceProcAddr.?);

    const proxy: vk.InstanceProxy = .init(handle, wrapper);

    return .{
        .handle = handle,
        .wrapper = wrapper,
        .proxy = proxy,
    };
}

pub fn deinit(self: Instance, gpa: std.mem.Allocator) void {
    self.proxy.destroyInstance(null);
    gpa.destroy(self.wrapper);
}
