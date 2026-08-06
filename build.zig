const std = @import("std");

pub fn build(b: *std.Build) void {
    const override_vulkan_registry = b.option([]const u8, "vulkan_registry", "Override the path to the Vulkan registry");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("api", .{
        .root_source_file = b.path("src/api.zig"),
        .target = target,
        .pic = true,
    });

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
                .{ .name = "vulkan", .module = vulkan },
            },
            .link_libc = switch (target.result.os.tag) {
                .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => true,
                else => false,
            },
        }),
    });

    switch (target.result.os.tag) {
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => {
            const scanner = @import("wayland").Scanner.create(b, .{});
            const wayland_protocols = b.dependency("wayland_protocols", .{});

            const wayland = b.createModule(.{
                .root_source_file = scanner.result,
                .target = target,
                .optimize = optimize,
            });

            scanner.addCustomProtocol(wayland_protocols.path("stable/xdg-shell/xdg-shell.xml"));
            scanner.addCustomProtocol(wayland_protocols.path("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"));
            scanner.addCustomProtocol(wayland_protocols.path("staging/cursor-shape/cursor-shape-v1.xml"));
            scanner.addCustomProtocol(wayland_protocols.path("unstable/tablet/tablet-unstable-v2.xml"));
            scanner.addCustomProtocol(wayland_protocols.path("unstable/pointer-constraints/pointer-constraints-unstable-v1.xml"));
            scanner.addCustomProtocol(wayland_protocols.path("unstable/relative-pointer/relative-pointer-unstable-v1.xml"));

            scanner.generate("wl_compositor", 1);
            scanner.generate("wl_output", 4);
            scanner.generate("wl_shm", 1);
            scanner.generate("wl_seat", 4);
            scanner.generate("wl_data_device_manager", 3);
            scanner.generate("xdg_wm_base", 3);
            scanner.generate("wp_cursor_shape_manager_v1", 2);
            scanner.generate("zxdg_decoration_manager_v1", 1);
            scanner.generate("zwp_tablet_manager_v2", 1);
            scanner.generate("zwp_pointer_constraints_v1", 1);
            scanner.generate("zwp_relative_pointer_manager_v1", 1);

            exe.root_module.addImport("wayland", wayland);

            const libxkbcommon = b.dependency("libxkbcommon", .{
                .target = target,
                .optimize = optimize,
                .@"xkb-config-root" = "/usr/share/X11/xkb",
                .@"x-locale-root" = "/usr/share/X11/locale",
            }).artifact("xkbcommon");
            const xkbcommon = b.dependency("xkbcommon", .{}).module("xkbcommon");
            xkbcommon.linkLibrary(libxkbcommon);

            exe.root_module.addImport("xkbcommon", xkbcommon);
        },
        .windows => {
            const win32 = b.dependency("win32", .{}).module("win32");
            exe.root_module.addImport("win32", win32);
        },
        .macos => {
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/Window/Cocoa.m"),
                .flags = &.{
                    "-fobjc-arc",
                },
                .language = .objective_c,
            });

            exe.root_module.linkFramework("Cocoa", .{});
            // exe.root_module.linkFramework("Foundation", .{});
        },
        else => {},
    }

    b.installArtifact(exe);
}
