const native_os = @import("builtin").os.tag;

const std = @import("std");
const DynLib = @import("DynLib.zig");
const Game = @import("Game.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const m = @import("math.zig");
const loader = @import("loader.zig");

const gravl = @import("real_engine");

pub const cube = struct {
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
};

const DefaultMesh = Renderer.Mesh(&.{loader.Obj.Vertex}, u32);

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
    try window.setMaxSize(.{ .width = 1200, .height = 675 });

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

    const assets_dir = try std.Io.Dir.cwd().openDir(io, assets_path, .{ .iterate = true });
    defer assets_dir.close(io);

    const obj_source = try assets_dir.readFileAlloc(io, "circuit_board/circuit_board.obj", gpa, .unlimited);
    defer gpa.free(obj_source);

    const obj: loader.Obj = try .parsefromSlice(gpa, obj_source, .{ .flip_uv_v = false });
    defer obj.free(gpa);

    const vertex_source = try assets_dir.readFileAlloc(io, "shaders/main.vert.spv", gpa, .unlimited);
    defer gpa.free(vertex_source);
    const fragment_source = try assets_dir.readFileAlloc(io, "shaders/main.frag.spv", gpa, .unlimited);
    defer gpa.free(fragment_source);

    const push_constant: Renderer.PushConstant(PushConstants, .{ .vertex = true, .fragment = true }) = try .init(renderer);
    defer push_constant.deinit(renderer);

    const vertex: Renderer.Shader(.vertex) = try .initFromSliceWithPushConstants(renderer, vertex_source, .{}, push_constant.range);
    defer vertex.deinit(renderer);

    const fragment: Renderer.Shader(.fragment) = try .initFromSliceWithPushConstants(renderer, fragment_source, .{}, push_constant.range);
    defer fragment.deinit(renderer);

    const mesh: DefaultMesh = try .init(renderer, .{ .vertices = .{obj.vertices}, .indices = obj.indices });
    defer mesh.deinit(renderer);

    var model_transform: m.Transform = .{};

    var camera: Camera = .{};

    var pointer_captured: bool = true;

    var wire_frame: f32 = 0.0;

    while (!window.should_close) {
        try window.poll(.{});
        _ = try io.sleep(.fromMilliseconds(8), .awake);

        const delta_time = getDeltaTime(io);
        const fps = 1.0 / delta_time;

        const frame: Renderer.Frame = try .begin(&renderer, window.size, .{ .clear_color = .{ 0.0, 0.3, 0.7, 1.0 } });
        frame.bindDefaultState();

        vertex.bind(frame);
        fragment.bind(frame);

        wire_frame += @floatCast(window.pointer.axis.vertical / 2);
        wire_frame = std.math.clamp(wire_frame, 0.0, 65.0);

        if (wire_frame > 0.0) frame.setPolygonMode(.{ .line = .{ .width = wire_frame } });

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

        if (window.keyboard.get(.f1) == .press) {
            std.log.info("pos: {any}, rot: {any}", .{ camera.position, camera.rotation });
        }

        switch (window.pointer.movement) {
            .position => {},
            .relative => |relative| {
                // if (relative.dx + relative.dy != 0) std.log.info("{any}", .{relative});
                camera.look(@floatCast(relative.dx), @floatCast(relative.dy));
            },
        }

        model_transform.rotation = model_transform.rotation.rotatedLocal(std.math.degreesToRadians(90.0 * delta_time), .y);

        const model = model_transform.matrix();
        const model2 = (m.Transform{ .position = .{ 1.0, 2.0, 2.0 } }).matrix();

        const view = camera.viewMatrix();
        const projection: m.Matrix4 = .perspectiveFovLh(std.math.degreesToRadians(90.0), window.size.aspect(), 0.01, 100.0);

        const mv = projection.mul(view);

        frame.setCullMode(.front);
        mesh.bind(frame);
        push_constant.push(frame, .{ .mvp = mv.mul(model) });
        mesh.draw(frame);
        push_constant.push(frame, .{ .mvp = mv.mul(model2) });
        mesh.draw(frame);

        try frame.end();
        try renderer.submit(frame);

        if (window.keyboard.isDown(.b)) std.log.info("fps: {d}, dt: {d}", .{ fps, delta_time });
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
            .mul(.translation(self.position));
    }

    const sensitivity = 0.005;

    pub fn look(self: *Camera, dx: f32, dy: f32) void {
        const yaw = if (self.isUpsideDown()) -dx else dx;

        self.rotation = self.rotation.rotatedLocal(
            -(yaw * sensitivity),
            .y,
        );

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

    pub fn move(self: *Camera, keyboard: *const Window.Keyboard, delta_time: f32) void {
        const matrix = self.rotation.matrix();
        const is_upside_down = self.isUpsideDown();

        const speed: f32 = if (keyboard.isDown(.left_control)) 0.25 else 2.0;

        const right: m.Vec3 = .{
            matrix.inner[0],
            matrix.inner[1],
            matrix.inner[2],
        };

        const forward: m.Vec3 = .{
            -matrix.inner[8],
            -matrix.inner[9],
            -matrix.inner[10],
        };

        const velocity: m.Vec3 = @splat(speed * delta_time);

        if (keyboard.isDown(.w)) self.position += forward * velocity;
        if (keyboard.isDown(.s)) self.position -= forward * velocity;
        if (keyboard.isDown(.d)) self.position -= right * velocity;
        if (keyboard.isDown(.a)) self.position += right * velocity;

        if (keyboard.isDown(.space)) self.position[1] += if (is_upside_down) -velocity[1] else velocity[1];
        if (keyboard.isDown(.left_shift)) self.position[1] -= if (is_upside_down) -velocity[1] else velocity[1];
    }

    pub fn isUpsideDown(self: Camera) bool {
        const q = self.rotation;
        const up_y = 2.0 * (q.y * q.y + q.w * q.w) - 1.0;
        return up_y < 0.0;
    }
};
