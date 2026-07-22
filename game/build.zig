const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const real_engine = b.dependency("real_engine", .{ .target = target, .optimize = optimize });

    const game = b.addLibrary(.{
        .name = "game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "real_engine_sdk", .module = real_engine.module("sdk") },
            },
            .pic = true,
        }),
        .linkage = .dynamic,
    });
    game.rdynamic = true;

    b.installArtifact(game);

    const real_engine_exe = real_engine.artifact("real_engine");

    b.installArtifact(real_engine_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(real_engine_exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addArtifactArg(game);
    if (b.args) |args| run_cmd.addArgs(args);
}
