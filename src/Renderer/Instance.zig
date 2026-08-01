const Instance = @This();

const std = @import("std");
const vk = @import("vulkan");

handle: vk.Instance,
wrapper: *vk.InstanceWrapper,
proxy: vk.InstanceProxy,

pub const api_version = vk.makeApiVersion(0, 1, 3, 0);

pub const InitError =
    vk.BaseWrapper.CreateInstanceError ||
    vk.BaseWrapper.EnumerateInstanceVersionError ||
    std.mem.Allocator.Error ||
    error{VulkanVersionTooOld};

pub fn init(
    gpa: std.mem.Allocator,
    vkb: vk.BaseWrapper,
    layers: []const [*:0]const u8,
    extensions: []const [*:0]const u8,
) InitError!Instance {
    const available_extensions = try vkb.enumerateInstanceExtensionPropertiesAlloc(null, gpa);
    defer gpa.free(available_extensions);

    const extension_available = try gpa.alloc(bool, extensions.len);
    defer gpa.free(extension_available);
    @memset(extension_available, false);

    for (available_extensions) |available_extension| {
        for (extensions, extension_available) |requested_extension, *is_available| {
            if (is_available.*) continue;

            if (std.mem.orderZ(u8, @ptrCast(&available_extension.extension_name), requested_extension) == .eq) is_available.* = true;
        }
    }

    for (extensions, extension_available) |requested_extension, is_available| {
        if (!is_available) std.log.info("vulkan extension {s} is not present", .{requested_extension});
    }

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

    const handle = vkb.createInstance(create_info, @ptrCast(@alignCast(gpa.ptr))) catch |err| return switch (err) {
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
    self.proxy.destroyInstance(@ptrCast(@alignCast(gpa.ptr)));
    gpa.destroy(self.wrapper);
}
