const Obj = @This();

const std = @import("std");

vertices: []Vertex = &.{},
indices: []u32 = &.{},

pub const Vertex = struct {
    position: [3]f32,
    uv: [2]f32,
    normal: [3]f32,
};

pub const Command = enum {
    /// Material library file
    mtllib,
    /// Use material
    usemtl,
    /// Object name
    o,
    /// Group name
    g,
    /// Vertex position
    v,
    /// Vertex texture coordinate
    vt,
    /// Vertex normal
    vn,
    /// Face
    f,
};

pub const ParseOptions = struct {
    flip_vertex_y: bool = true,
    flip_uv_v: bool = true,
};

pub const ParseError = (std.Io.Reader.Error ||
    std.mem.Allocator.Error ||
    std.fmt.ParseFloatError ||
    std.fmt.ParseIntError ||
    error{ StreamTooLong, InvalidCharacter, InvalidCommand, InvalidFormat });

pub fn parsefromSlice(gpa: std.mem.Allocator, s: []const u8, options: ParseOptions) ParseError!Obj {
    var reader: std.Io.Reader = .fixed(s);
    return .parse(gpa, &reader, options);
}

pub fn parse(gpa: std.mem.Allocator, r: *std.Io.Reader, options: ParseOptions) ParseError!Obj {
    var positions: std.ArrayList([3]f32) = .empty;
    var uvs: std.ArrayList([2]f32) = .empty;
    var normals: std.ArrayList([3]f32) = .empty;

    defer positions.deinit(gpa);
    defer uvs.deinit(gpa);
    defer normals.deinit(gpa);

    var vertices: std.ArrayList(Vertex) = .empty;
    var indices: std.ArrayList(u32) = .empty;

    errdefer vertices.deinit(gpa);
    errdefer indices.deinit(gpa);

    while (try r.takeDelimiter('\n')) |line| {
        if (line.len == 0 or line[0] == '#') continue;

        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const command_str = std.mem.trim(u8, tokens.next() orelse continue, "\t\r");
        if (command_str.len == 0) continue;

        const command = std.meta.stringToEnum(Command, command_str) orelse {
            std.log.err("invalid command: '{s}'", .{command_str});
            return error.InvalidCommand;
        };

        switch (command) {
            .mtllib => {
                _ = tokens.next().?; // path
            },
            .usemtl => {
                _ = tokens.next().?;
            },
            .o => {
                _ = tokens.next().?;
            },
            .g => {
                _ = tokens.next().?;
            },
            .v => {
                const x = try parseFloat(tokens.next());
                const y = try parseFloat(tokens.next());
                const z = try parseFloat(tokens.next());
                const position: [3]f32 = .{
                    x,
                    if (options.flip_vertex_y) -y else y,
                    z,
                };
                try positions.append(gpa, position);
            },
            .vt => {
                const u = try parseFloat(tokens.next());
                const v = try parseFloat(tokens.next());
                const uv: [2]f32 = .{
                    u,
                    if (options.flip_uv_v) -v else v,
                };
                try uvs.append(gpa, uv);
            },
            .vn => {
                const normal: [3]f32 = .{
                    try parseFloat(tokens.next()),
                    try parseFloat(tokens.next()),
                    try parseFloat(tokens.next()),
                };
                try normals.append(gpa, normal);
            },
            .f => {
                while (tokens.next()) |vertex_data| {
                    const ref = try parseVertex(vertex_data);
                    if (ref.position >= positions.items.len) return error.InvalidFormat;

                    const position = positions.items[ref.position];
                    const uv = if (ref.uv) |i| uvs.items[i] else .{ 0, 0 };
                    const normal = if (ref.normal) |i| normals.items[i] else .{ 0, 0, 0 };

                    const vertex: Vertex = .{
                        .position = position,
                        .uv = uv,
                        .normal = normal,
                    };

                    try vertices.append(gpa, vertex);

                    try indices.append(gpa, @intCast(vertices.items.len - 1));
                }
            },
        }
    }

    return .{
        .vertices = try vertices.toOwnedSlice(gpa),
        .indices = try indices.toOwnedSlice(gpa),
    };
}

pub fn free(self: Obj, gpa: std.mem.Allocator) void {
    gpa.free(self.vertices);
    gpa.free(self.indices);
}

const VertexRef = struct {
    position: usize,
    uv: ?usize,
    normal: ?usize,
};

fn parseVertex(token: []const u8) (std.fmt.ParseIntError || error{InvalidFormat})!VertexRef {
    var parts = std.mem.splitScalar(u8, token, '/');

    const position = try std.fmt.parseInt(usize, parts.next() orelse return error.InvalidFormat, 10);

    const uv = if (parts.next()) |part|
        if (part.len > 0) try std.fmt.parseInt(usize, part, 10) else null
    else
        null;

    const normal = if (parts.next()) |part| try std.fmt.parseInt(usize, part, 10) else null;

    return .{
        .position = position - 1,
        .uv = if (uv) |i| i - 1 else null,
        .normal = if (normal) |i| i - 1 else null,
    };
}

fn parseFloat(s: ?[]const u8) std.fmt.ParseFloatError!f32 {
    const trimmed = std.mem.trim(u8, s.?, "\t\r");
    return std.fmt.parseFloat(f32, trimmed);
}
