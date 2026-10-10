const DebugMessenger = @This();

const std = @import("std");
const vk = @import("vulkan");

const Instance = @import("Instance.zig");

handle: vk.DebugUtilsMessengerEXT,

pub fn init(gpa: std.mem.Allocator, instance: Instance) vk.InstanceWrapper.CreateDebugUtilsMessengerEXTError!DebugMessenger {
    const create_info: *const vk.DebugUtilsMessengerCreateInfoEXT = &.{
        .message_severity = .{
            // .verbose_bit_ext = true,
            // .info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = callback,
        .p_user_data = null,
    };

    const handle = try instance.proxy.createDebugUtilsMessengerEXT(create_info, @ptrCast(@alignCast(gpa.ptr)));
    return .{ .handle = handle };
}

pub fn deinit(self: DebugMessenger, gpa: std.mem.Allocator, instance: Instance) void {
    instance.proxy.destroyDebugUtilsMessengerEXT(self.handle, @ptrCast(@alignCast(gpa.ptr)));
}

fn callback(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    userdata: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_types;
    _ = userdata;

    const level: std.log.Level = if (severity.error_bit_ext)
        .err
    else if (severity.warning_bit_ext)
        .warn
    else if (severity.info_bit_ext)
        .info
    else if (severity.verbose_bit_ext)
        .debug
    else
        unreachable;

    switch (level) {
        inline else => |l| {
            const msg = data.?;
            const log = std.options.logFn;
            log(l, .vulkan, "[{s}] {d}: {s}", .{ msg.p_message_id_name orelse "", msg.message_id_number, msg.p_message orelse "" });
        },
    }

    return .false;
}
