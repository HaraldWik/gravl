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
    try window.open(init.gpa, init.minimal, .{
        .app_id = game.id,
        .title = game.name,
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

    try window.setTitle("Hello, World!");

    while (!window.should_close) {
        try window.poll(.{});
        _ = try io.sleep(.fromMicroseconds(16), .real);

        const delta_time = getDeltaTime(io);
        const fps = 1.0 / delta_time;

        try io.sleep(.fromMilliseconds(1), .real);

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

        try renderer.submit(window.size);
        try renderer.resize(window.size);

        // for (0..Window.Keyboard.Key.count) |i| {
        //     const key: Window.Keyboard.Key = @enumFromInt(i);
        //     const state = window.keyboard.get(key);
        //     switch (state) {
        //         .none => {},
        //         .press, .release, .repeat => std.debug.print("{t}: {t}\n", .{ state, key }),
        //     }
        // }

        if (window.keyboard.isDown(.b)) std.log.info("fps: {d}", .{fps});
    }
}

pub fn getDeltaTime(io: std.Io) f32 {
    const static = struct {
        var previous: ?std.Io.Timestamp = null;
    };

    const now: std.Io.Timestamp = .now(io, .real);
    const prev = static.previous orelse {
        static.previous = now;
        return getDeltaTime(io);
    };

    const dt_ns = prev.durationTo(now);
    static.previous = now;

    return @as(f32, @floatFromInt(dt_ns.nanoseconds)) / 1_000_000_000.0;
}
