const native_os = @import("builtin").os.tag;

const std = @import("std");
const DynLib = @import("DynLib.zig");
const Game = @import("Game.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");

const real_engine = @import("real_engine");

const vertices: []const Vertex = &.{
    .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.4, 0.4, 0.4 } },
    .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0 } },
    .{ .position = .{ 0.5, 0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0 } },
    .{ .position = .{ -0.5, 0.5, 0.0 }, .color = .{ 1.0, 1.0, 0.0 } },
};

const indices: []const u32 = &.{
    // Triangle 1
    0, 1, 2,

    // Triangle 2
    2, 3, 0,
};

const Vertex = extern struct {
    position: [3]f32,
    color: [3]f32,
};

const DefaultMesh = Renderer.Mesh(&.{Vertex}, u32);

const PushConstants = extern struct {
    offset: [3]f32,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    const bin_path = args.next().?;

    var game_dynlib: DynLib = try .openZ(args.next() orelse absolute_path: {
        const arena = init.arena.allocator();

        const libgame = switch (native_os) {
            .windows => "game.dll",
            else => "libgame.so",
        };

        const path = try std.Io.Dir.cwd().realPathFileAlloc(io, try std.Io.Dir.path.join(arena, &.{ std.Io.Dir.path.dirname(bin_path) orelse ".", libgame }), arena);
        break :absolute_path path;
    });
    defer game_dynlib.close();

    const ffi_table: Game.ffi.Table = try .load(&game_dynlib);

    const game: Game = .init(ffi_table);
    defer game.deinit();

    std.log.info("{s} ({f})", .{ game.name, game.version });

    var window: Window = undefined;
    try window.open(gpa, init.minimal, .{
        .app_id = game.id,
        .title = game.name,
        .size = .{
            .width = 1200,
            .height = 675,
        },
    });
    defer window.close();
    try window.setPointerVisible(false);
    try window.setPointerConstraint(.confined);
    try window.setPointerRelative(true);

    var renderer: Renderer = try .init(gpa, &window);
    defer renderer.deinit();

    const asset_paths: []const [:0]const u8 = &.{
        "assets",
        "../assets",
        "../../assets",
    };

    const assets_path: [:0]const u8 = path: for (asset_paths) |path| {
        std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        break :path path;
    } else return error.NoAssetDir;

    const dir = try std.Io.Dir.cwd().openDir(io, assets_path, .{ .iterate = true });

    const shaders = try dir.openDir(io, "shaders", .{});
    defer shaders.close(io);

    const vertex_source = try shaders.readFileAlloc(io, "main.vert.spv", gpa, .unlimited);
    defer gpa.free(vertex_source);
    const fragment_source = try shaders.readFileAlloc(io, "main.frag.spv", gpa, .unlimited);
    defer gpa.free(fragment_source);

    const vertex2_source = try shaders.readFileAlloc(io, "main2.vert.spv", gpa, .unlimited);
    defer gpa.free(vertex2_source);

    const push_constants: Renderer.PushConstants(PushConstants) = try .init(renderer);
    defer push_constants.deinit(renderer);

    const vertex: Renderer.Shader(.vertex) = try .initFromSliceWithPushConstants(renderer, vertex_source, .{}, push_constants);
    defer vertex.deinit(renderer);

    const fragment: Renderer.Shader(.fragment) = try .initFromSliceWithPushConstants(renderer, fragment_source, .{}, push_constants);
    defer fragment.deinit(renderer);

    const vertex2: Renderer.Shader(.vertex) = try .initFromSliceWithPushConstants(renderer, vertex2_source, .{}, push_constants);
    defer vertex2.deinit(renderer);

    const mesh: DefaultMesh = try .init(renderer, .{ .vertices = .{vertices}, .indices = indices });
    defer mesh.deinit(renderer);

    var push: PushConstants = .{ .offset = @splat(0) };

    while (!window.should_close) {
        try window.poll(.{});
        _ = try io.sleep(.fromMilliseconds(8), .awake);

        const delta_time = getDeltaTime(io);
        const fps = 1.0 / delta_time;

        try renderer.acquire(window.size);
        renderer.bindDefaultState();

        const speed = 2.0;

        if (window.keyboard.isDown(.escape)) window.should_close = true;

        if (window.keyboard.isDown(.a)) {
            push.offset[0] -= delta_time * speed;
        }
        if (window.keyboard.isDown(.d)) {
            push.offset[0] += delta_time * speed;
        }
        if (window.keyboard.isDown(.s)) {
            push.offset[1] += delta_time * speed;
        }
        if (window.keyboard.isDown(.w)) {
            push.offset[1] -= delta_time * speed;
        }

        push_constants.push(renderer, push);

        vertex.bind(renderer);
        fragment.bind(renderer);

        if (window.keyboard.isDown(.space)) {
            vertex2.bind(renderer);
            renderer.setPolygonMode(.{ .line = .{ .width = 1.2 } });
        }

        mesh.bind(renderer);
        mesh.draw(renderer);

        try renderer.submit(window.size);

        // std.debug.print("{f}", .{window.keyboard});

        if (window.keyboard.isDown(.b)) std.log.info("fps: {d}", .{fps});
    }
}

pub fn getDeltaTime(io: std.Io) f32 {
    const static = struct {
        var previous: ?std.Io.Timestamp = null;
    };

    const now: std.Io.Timestamp = .now(io, .real);

    const previous = static.previous orelse {
        static.previous = now;
        return 0.0;
    };

    static.previous = now;

    const duration = previous.durationTo(now);
    return @as(f32, @floatFromInt(duration.toMilliseconds())) / 1000.0;
}
