const std = @import("std");
const DynLib = @import("DynLib.zig");
const Game = @import("Game.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");

const real_engine = @import("real_engine");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(init.arena.allocator());
    _ = args.skip();

    var game_dynlib: DynLib = try .open(args.next() orelse "game");
    defer game_dynlib.close();

    const ffi_table: Game.ffi.Table = try .load(&game_dynlib);

    const game: Game = .init(ffi_table);
    defer game.deinit();

    std.log.info("{s} ({f})", .{ game.name, game.version });

    var window: Window = undefined;
    try window.open(init, .{
        .app_id = .hello,
        .title = "Hello, world",
        .size = .{
            .width = 300,
            .height = 300,
        },
    });
    defer window.close();

    var renderer: Renderer = try .init(gpa, &window);
    defer renderer.deinit();

    const shaders = try std.Io.Dir.cwd().openDir(io, "../shaders", .{});
    defer shaders.close(io);

    const vertex_source = try shaders.readFileAlloc(io, "main.vert.spv", gpa, .unlimited);
    defer gpa.free(vertex_source);
    const fragment_source = try shaders.readFileAlloc(io, "main.frag.spv", gpa, .unlimited);
    defer gpa.free(fragment_source);

    const vertex2_source = try shaders.readFileAlloc(io, "main2.vert.spv", gpa, .unlimited);
    defer gpa.free(vertex2_source);

    const vertex: Renderer.ShaderObject = try .init(renderer.gpa, renderer.device, .{
        .stage = .vertex,
        .next_stage = .fragment,
        .source = vertex_source,
    });
    defer vertex.deinit(renderer.gpa, renderer.device);

    const fragment: Renderer.ShaderObject = try .init(renderer.gpa, renderer.device, .{
        .stage = .fragment,
        .source = fragment_source,
    });
    defer fragment.deinit(renderer.gpa, renderer.device);

    const vertex2: Renderer.ShaderObject = try .init(renderer.gpa, renderer.device, .{
        .stage = .vertex,
        .next_stage = .fragment,
        .source = vertex2_source,
    });
    defer vertex2.deinit(renderer.gpa, renderer.device);

    // const pipeline: Renderer.Pipeline = try .init(renderer.gpa, renderer.device, renderer.swapchain, .{
    //     .fragment_source = fragment_source,
    //     .vertex_source = vertex_source,
    // });
    // defer pipeline.deinit(renderer.gpa, renderer.device);

    while (!window.should_close) {
        try window.poll();

        try renderer.acquire(window.size);

        renderer.bindShader(fragment);
        renderer.bindShader(vertex);
        renderer.bindShader(.{ .handle = .null_handle, .stage = .geometry });
        renderer.bindShader(.{ .handle = .null_handle, .stage = .tessellation_control });
        renderer.bindShader(.{ .handle = .null_handle, .stage = .tessellation_evaluation });

        if (renderer.command_handler.frame_index % 3000 > 1500) {
            renderer.bindShader(vertex2);
        }

        renderer.draw();

        // renderer.bindPipeline(pipeline);

        try renderer.submit(window.size);
        try renderer.resize(window.size);
    }
}
