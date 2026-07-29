const std = @import("std");
const gv = @import("gravl");

comptime {
    _ = gv;
}

pub const game_info: gv.Game = .{
    .id = "example_game",
    .name = "Example Game",
};
