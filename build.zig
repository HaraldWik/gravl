const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk = b.addModule("sdk", .{
        .root_source_file = b.path("src/sdk.zig"),
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

    const win32 = b.dependency("win32", .{}).module("win32");

    const exe = b.addExecutable(.{
        .name = "real_engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wayland", .module = wayland },
                .{ .name = "win32", .module = win32 },
            },
            .link_libc = true,
        }),
    });

    b.installArtifact(exe);

    // const run_step = b.step("run", "Run the app");
    // const run_cmd = b.addRunArtifact(exe);
    // run_step.dependOn(&run_cmd.step);
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| run_cmd.addArgs(args);

    const sdk_tests = b.addTest(.{
        .root_module = sdk,
    });

    const run_mod_tests = b.addRunArtifact(sdk_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
