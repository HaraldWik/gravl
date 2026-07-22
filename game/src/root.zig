const std = @import("std");
const sdk = @import("real_engine_sdk");

comptime {
    _ = sdk;
}

pub const game_info: sdk.Game = .{
    .id = "my_game",
    .name = "My Game",
};
