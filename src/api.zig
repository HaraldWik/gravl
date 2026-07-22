const game = @import("root");

pub const Game = @import("Game.zig");

export fn info() Game.ffi.Info {
    if (!@hasDecl(game, "game_info")) @compileError("Missing decleration game_info, no game info found");
    const game_info: Game = @field(game, "game_info");
    return .{
        .id = game_info.id.ptr,
        .name = game_info.name.ptr,
        .version = &game_info.version,
    };
}
