const native_os = @import("builtin").os.tag;

const std = @import("std");
const DynLib = @import("DynLib.zig");
const Game = @import("Game.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const m = @import("math.zig");

const real_engine = @import("real_engine");

const vertices: []const Vertex = &.{
    // Front face (z = -0.5)
    .{ .position = .{ -0.5, -0.5, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .position = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .position = .{ 0.5, 0.5, -0.5 }, .color = .{ 0, 0, 1 } },
    .{ .position = .{ -0.5, 0.5, -0.5 }, .color = .{ 1, 1, 0 } },

    // Back face (z = 0.5)
    .{ .position = .{ -0.5, -0.5, 0.5 }, .color = .{ 1, 0, 1 } },
    .{ .position = .{ 0.5, -0.5, 0.5 }, .color = .{ 0, 1, 1 } },
    .{ .position = .{ 0.5, 0.5, 0.5 }, .color = .{ 1, 1, 1 } },
    .{ .position = .{ -0.5, 0.5, 0.5 }, .color = .{ 0.5, 0.5, 0.5 } },
};

const indices: []const u32 = &.{
    0, 1, 2,
    2, 3, 0,
    4, 6, 5,
    6, 4, 7,
    0, 3, 7,
    7, 4, 0,
    1, 5, 6,
    6, 2, 1,
    3, 2, 6,
    6, 7, 3,
    0, 4, 5,
    5, 1, 0,
};

const Vertex = extern struct {
    position: [3]f32,
    color: [3]f32,
};

const DefaultMesh = Renderer.Mesh(&.{Vertex}, u32);

const PushConstants = extern struct {
    mvp: m.Matrix4 = .identity,
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
    try window.setPointerConstraint(.locked);
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

    var model_transform: m.Transform = .{};

    var camera: Camera = .{};

    var pointer_captured: bool = true;

    while (!window.should_close) {
        try window.poll(.{});
        _ = try io.sleep(.fromMilliseconds(8), .awake);

        const delta_time = getDeltaTime(io);
        const fps = 1.0 / delta_time;

        try renderer.acquire(window.size);
        renderer.bindDefaultState();

        vertex.bind(renderer);
        fragment.bind(renderer);

        if (window.keyboard.isDown(.space)) {
            vertex2.bind(renderer);
            renderer.setPolygonMode(.{ .line = .{ .width = 1.2 } });
        }

        if (window.keyboard.get(.escape) == .press) {
            pointer_captured = !pointer_captured;

            if (pointer_captured) {
                try window.setPointerVisible(false);
                try window.setPointerConstraint(.locked);
                try window.setPointerRelative(true);
            } else {
                try window.setPointerVisible(true);
                try window.setPointerConstraint(.none);
                try window.setPointerRelative(false);
            }
        }

        camera.move(&window.keyboard, delta_time);

        switch (window.pointer.movement) {
            .position => {},
            .relative => |relative| {
                // if (relative.dx + relative.dy != 0) std.log.info("{any}", .{relative});
                camera.look(@floatCast(relative.dx), @floatCast(relative.dy));
            },
        }

        model_transform.rotation = model_transform.rotation.rotatedLocal(std.math.degreesToRadians(90.0 * delta_time), .y);

        const model = model_transform.matrix();
        const model2 = (m.Transform{ .position = .{ 1.0, 0.0, 2.0 } }).matrix();

        const view = camera.viewMatrix();
        const projection: m.Matrix4 = .perspectiveFovLh(std.math.degreesToRadians(90.0), window.size.aspect(), 0.1, 100.0);

        const mv = projection.mul(view);

        mesh.bind(renderer);
        push_constants.push(renderer, .{ .mvp = mv.mul(model) });
        mesh.draw(renderer);
        push_constants.push(renderer, .{ .mvp = mv.mul(model2) });
        mesh.draw(renderer);

        try renderer.submit(window.size);

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

pub const Camera = struct {
    position: m.Vec3 = @splat(0),
    rotation: m.Quaternion = .identity,

    pub fn viewMatrix(self: Camera) m.Matrix4 {
        return self.rotation
            .inversed()
            .matrix()
            .mul(.translation(-self.position));
    }

    const sensitivity = 0.005;

    pub fn look(self: *Camera, dx: f32, dy: f32) void {
        self.rotation = self.rotation.rotatedLocal(-(dx * sensitivity), .y);

        const q = self.rotation;

        const forward: m.Vec3 = .{
            2.0 * (q.x * q.z + q.w * q.y),
            2.0 * (q.y * q.z - q.w * q.x),
            2.0 * (q.y * q.y + q.x * q.x) - 1.0,
        };

        const pitch = std.math.asin(-forward[1]);

        const limit = std.math.degreesToRadians(89.0);
        const new_pitch = std.math.clamp(
            pitch + dy * sensitivity,
            -limit,
            limit,
        );

        self.rotation = self.rotation.rotatedWorld(
            new_pitch - pitch,
            .x,
        );
    }

    const speed = 3.0;

    pub fn move(self: *Camera, keyboard: *const Window.Keyboard, delta_time: f32) void {
        const amount = delta_time * speed;

        const matrix = self.rotation.matrix();

        const right = m.Vec3{
            matrix.inner[0],
            matrix.inner[1],
            matrix.inner[2],
        };

        const forward = m.Vec3{
            -matrix.inner[8],
            -matrix.inner[9],
            -matrix.inner[10],
        };

        if (keyboard.isDown(.w)) {
            self.position -= forward * @as(m.Vec3, @splat(amount));
        }
        if (keyboard.isDown(.s)) {
            self.position += forward * @as(m.Vec3, @splat(amount));
        }
        if (keyboard.isDown(.d)) {
            self.position += right * @as(m.Vec3, @splat(amount));
        }
        if (keyboard.isDown(.a)) {
            self.position -= right * @as(m.Vec3, @splat(amount));
        }
    }
};
