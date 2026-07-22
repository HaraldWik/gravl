const Game = @This();

const std = @import("std");

const DynLib = @import("DynLib.zig");

id: [:0]const u8,
name: [:0]const u8,
version: std.SemanticVersion = .{ .major = 1, .minor = 0, .patch = 0 },

pub fn init(ffi_table: ffi.Table) Game {
    const info = ffi_table.info();
    return .{
        .id = std.mem.span(info.id),
        .name = std.mem.span(info.name),
        .version = if (info.version) |version| version.* else .{ .major = 1, .minor = 0, .patch = 0 },
    };
}

pub fn deinit(self: Game) void {
    _ = self;
}

pub const ffi = struct {
    pub const Info = extern struct {
        id: [*:0]const u8,
        name: [*:0]const u8,
        version: ?*const std.SemanticVersion = null,
    };

    pub const Table = struct {
        info: *const fn () callconv(.c) Info,

        pub fn load(dynlib: *DynLib) !Table {
            var table: Table = undefined;
            inline for (std.meta.fields(Table)) |field| {
                @field(table, field.name) = dynlib.lookup(field.type, field.name) orelse return error.TableLookup;
            }
            return table;
        }
    };
};
