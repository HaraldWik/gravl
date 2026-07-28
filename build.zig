const std = @import("std");

pub fn build(b: *std.Build) void {
    const override_vulkan_registry = b.option([]const u8, "vulkan_registry", "Override the path to the Vulkan registry");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const api = b.addModule("api", .{
        .root_source_file = b.path("src/api.zig"),
        .target = target,
        .pic = true,
    });

    const scanner = @import("wayland").Scanner.create(b, .{});
    const wayland_protocols = b.dependency("wayland_protocols", .{});

    const wayland = b.createModule(.{
        .root_source_file = scanner.result,
        .target = target,
        .optimize = optimize,
    });
    // wayland.linkSystemLibrary("wayland-client", .{ .needed = true });

    scanner.addCustomProtocol(wayland_protocols.path("stable/xdg-shell/xdg-shell.xml"));
    scanner.addCustomProtocol(wayland_protocols.path("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"));
    scanner.addCustomProtocol(wayland_protocols.path("staging/cursor-shape/cursor-shape-v1.xml"));
    scanner.addCustomProtocol(wayland_protocols.path("unstable/tablet/tablet-unstable-v2.xml"));

    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_seat", 4);
    scanner.generate("xdg_wm_base", 3);
    // scanner.generate("xdg_activation_v1", 1);
    scanner.generate("zxdg_decoration_manager_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 2);
    scanner.generate("zwp_tablet_manager_v2", 1);

    const xcb = b.dependency("xcb", .{ .target = target, .optimize = optimize }).module("xcb");

    const win32 = b.dependency("win32", .{}).module("win32");

    const vulkan_registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");

    const vulkan_registry_path: std.Build.LazyPath = if (override_vulkan_registry) |path|
        .{ .cwd_relative = path }
    else
        vulkan_registry;

    const vulkan = b.dependency("vulkan", .{ .registry = vulkan_registry_path }).module("vulkan-zig");

    const exe = b.addExecutable(.{
        .name = "gravl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wayland", .module = wayland },
                .{ .name = "xcb", .module = xcb },
                .{ .name = "win32", .module = win32 },

                .{ .name = "vulkan", .module = vulkan },
            },
            .link_libc = switch (target.result.os.tag) {
                .windows => false,
                else => true,
            },
        }),
    });

    exe.root_module.linkSystemLibrary("xcb", .{});

    b.installArtifact(exe);

    // const run_step = b.step("run", "Run the app");
    // const run_cmd = b.addRunArtifact(exe);
    // run_step.dependOn(&run_cmd.step);
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| run_cmd.addArgs(args);

    const api_tests = b.addTest(.{
        .root_module = api,
    });

    const run_mod_tests = b.addRunArtifact(api_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
