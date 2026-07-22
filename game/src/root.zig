const std = @import("std");
const api = @import("real_engine_api");

comptime {
    _ = api;
}

pub const game_info: api.Game = .{
    .id = "my_game",
    .name = "My Game",
};
