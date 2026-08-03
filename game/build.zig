const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gravl = b.dependency("gravl", .{ .target = target, .optimize = optimize });

    const game = b.addLibrary(.{
        .name = "game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gravl", .module = gravl.module("api") },
            },
            .pic = true,
        }),
        .linkage = .dynamic,
    });
    game.rdynamic = true;

    b.installArtifact(game);

    const gravl_exe = gravl.artifact("gravl");

    b.installArtifact(gravl_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(gravl_exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addArtifactArg(game);
    if (b.args) |args| run_cmd.addArgs(args);

    const package_step = b.step("package", "Package everything into a folder");
    package_step.dependOn(b.getInstallStep());

    const package_name = b.fmt("pkg-{t}-{t}", .{ target.result.cpu.arch, target.result.os.tag });

    const package_gravl_exe = b.addInstallArtifact(gravl_exe, .{ .dest_dir = .{ .override = .{ .custom = b.pathJoin(&.{ package_name, "bin" }) } } });
    package_step.dependOn(&package_gravl_exe.step);
    const package_game = b.addInstallArtifact(game, .{ .dest_dir = .{ .override = .{ .custom = b.pathJoin(&.{ package_name, "bin" }) } } });
    package_step.dependOn(&package_game.step);
    const package_assets = b.addInstallDirectory(.{ .source_dir = b.path("../assets/"), .install_dir = .{ .custom = package_name }, .install_subdir = "assets" });
    package_step.dependOn(&package_assets.step);
}
