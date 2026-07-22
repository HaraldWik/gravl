const std = @import("std");
const DynLib = @import("DynLib.zig");
const Game = @import("Game.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");

const real_engine = @import("real_engine");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

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

    while (!window.should_close) {
        try window.poll();
    }
}
