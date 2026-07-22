const Surface = @This();

const builtin = @import("builtin");

const std = @import("std");
const vk = @import("vulkan");

const Window = @import("../Window.zig");
const Wayland = @import("../Window/Wayland.zig");
const X = @import("../Window/X.zig");
const Win32 = @import("../Window/Win32.zig");
const Cocoa = @import("../Window/Cocoa.zig");

const Instance = @import("Instance.zig");

handle: vk.SurfaceKHR,

const WaylandError = vk.InstanceWrapper.CreateWaylandSurfaceKHRError;
const XError = vk.InstanceWrapper.CreateXcbSurfaceKHRError;
const Win32Error = vk.InstanceWrapper.CreateWin32SurfaceKHRError;
const CocoaError = vk.InstanceWrapper.CreateMacOsSurfaceMVKError;

pub const InitError = switch (builtin.os.tag) {
    .linux, .freebsd, .netbsd, .openbsd => WaylandError || XError,
    .windows => Win32Error,
    .macos => CocoaError,
    else => error{},
};

pub fn init(instance: Instance, window: *Window) InitError!Surface {
    return switch (builtin.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd => switch (window.inner) {
            .wayland => .initWayland(instance, &window.inner.wayland),
            .x11 => .initX(instance, &window.inner.x11),
        },
        .windows => .initWin32(instance, &window.inner),
        .macos => .initCocoa(instance, &window.inner),
        else => @compileError("unsupported platform"),
    };
}

pub fn deinit(self: Surface, instance: Instance) void {
    instance.proxy.destroySurfaceKHR(self.handle, null);
}

fn initWayland(instance: Instance, wayland: *Wayland) WaylandError!Surface {
    const create_info: *const vk.WaylandSurfaceCreateInfoKHR = &.{
        .display = @ptrCast(wayland.display),
        .surface = @ptrCast(wayland.surface),
    };

    const handle = try instance.proxy.createWaylandSurfaceKHR(create_info, null);
    return .{ .handle = handle };
}

fn initX(instance: Instance, x: *X) XError!Surface {
    _ = x;
    const create_info: *const vk.XcbSurfaceCreateInfoKHR = &.{
        .connection = undefined,
        .window = 0,
    };

    const handle = try instance.proxy.createXcbSurfaceKHR(create_info, null);
    return .{ .handle = handle };
}

fn initWin32(instance: Instance, win32: *Win32) Win32Error!Surface {
    const create_info: *const vk.Win32SurfaceCreateInfoKHR = &.{
        .hinstance = win32.hinstance,
        .hwnd = win32.hwnd,
    };

    const handle = try instance.proxy.createWin32SurfaceKHR(create_info, null);
    return .{ .handle = handle };
}

fn initCocoa(instance: Instance, cocoa: *Cocoa) CocoaError!Surface {
    _ = cocoa;
    const create_info: *const vk.MacOSSurfaceCreateInfoMVK = &.{
        .p_view = undefined,
    };

    const handle = try instance.proxy.createMacOsSurfaceMVK(create_info, null);
    return .{ .handle = handle };
}
