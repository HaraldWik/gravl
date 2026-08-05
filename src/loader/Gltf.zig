const Gltf = @This();

const std = @import("std");

asset: Asset,

buffers: []Buffer = &.{},
buffer_views: []BufferView = &.{},
accessors: []Accessor = &.{},

images: []Image = &.{},
samplers: []Sampler = &.{},
textures: []Texture = &.{},

materials: []Material = &.{},
meshes: []Mesh = &.{},
nodes: []Node = &.{},
scenes: []Scene = &.{},

scene: ?usize = null,

pub const Asset = struct {
    version: []const u8,
    generator: ?[]const u8 = null,
};

pub const Buffer = struct {
    uri: ?[]const u8 = null,
    byte_length: usize,
};

pub const BufferView = struct {
    buffer: usize,
    byte_offset: usize = 0,
    byte_length: usize,
    byte_stride: ?usize = null,
    target: ?u32 = null,
};

pub const Accessor = struct {
    buffer_view: ?usize = null,
    byte_offset: usize = 0,
    component_type: u32,
    normalized: bool = false,
    count: usize,
    type: Type,

    pub const Type = enum {
        scalar,
        vec2,
        vec3,
        vec4,
        mat2,
        mat3,
        mat4,
    };
};

pub const Image = struct {
    uri: ?[]const u8 = null,
    buffer_view: ?usize = null,
    mime_type: ?[]const u8 = null,
};

pub const Sampler = struct {
    mag_filter: ?u32 = null,
    min_filter: ?u32 = null,
    wrap_s: u32 = 10497, // REPEAT
    wrap_t: u32 = 10497,
};

pub const Texture = struct {
    sampler: ?usize = null,
    source: usize, // index into images
};

pub const Material = struct {
    name: ?[]const u8 = null,

    base_color: [4]f32 = .{ 1, 1, 1, 1 },
    metallic: f32 = 1.0,
    roughness: f32 = 1.0,

    base_color_texture: ?usize = null,
    metallic_roughness_texture: ?usize = null,
    normal_texture: ?usize = null,
    occlusion_texture: ?usize = null,
    emissive_texture: ?usize = null,

    emissive_factor: [3]f32 = .{ 0, 0, 0 },
};

pub const Mesh = struct {
    name: ?[]const u8 = null,
    primitives: []Primitive,
};

pub const Primitive = struct {
    attributes: Attributes,
    indices: ?usize = null,
    material: ?usize = null,

    topology: Topology = .triangle_list,

    pub const Attributes = struct {
        position: usize,
        normal: ?usize = null,
        texcoord_0: ?usize = null,
        tangent: ?usize = null,
        color_0: ?usize = null,
        joints_0: ?usize = null,
        weights_0: ?usize = null,
    };

    pub const Topology = enum(u32) {
        points = 0,
        line_list = 1,
        line_loop = 2,
        line_strip = 3,
        triangle_list = 4,
        triangle_strip = 5,
        triangle_fan = 6,
    };
};

pub const Node = struct {
    name: ?[]const u8 = null,

    mesh: ?usize = null,
    children: []usize = &.{},

    translation: [3]f32 = .{ 0, 0, 0 },
    rotation: [4]f32 = .{ 0, 0, 0, 1 },
    scale: [3]f32 = .{ 1, 1, 1 },

    matrix: ?[16]f32 = null,
};

pub const Scene = struct {
    name: ?[]const u8 = null,
    nodes: []usize,
};

pub fn parseFromSlice(gpa: std.mem.Allocator, s: []const u8) std.json.Parsed(Gltf) {
    return std.json.parseFromSlice(Gltf, gpa, s, .{ .ignore_unknown_fields = true });
}

pub const CpuMesh = extern struct {
    positions: [][3]f32,
    indices: []u32,
};

pub fn getPrimitive(
    self: *const Gltf,
    allocator: std.mem.Allocator,
    mesh_index: usize,
    primitive_index: usize,
) !CpuMesh {
    const primitive = self.meshes[mesh_index].primitives[primitive_index];

    const pos_accessor = self.accessors[primitive.attributes.position];
    const pos_view = self.buffer_views[pos_accessor.buffer_view.?];
    const pos_buffer = self.loaded_buffers[pos_view.buffer];

    const pos_offset = pos_view.byte_offset + pos_accessor.byte_offset;
    const pos_stride = pos_view.byte_stride orelse @sizeOf([3]f32);

    var positions = try allocator.alloc([3]f32, pos_accessor.count);

    for (0..pos_accessor.count) |i| {
        const start = pos_offset + i * pos_stride;

        positions[i] = std.mem.bytesToValue(
            [3]f32,
            pos_buffer[start .. start + @sizeOf([3]f32)],
        );
    }

    var indices: []u32 = &.{};

    if (primitive.indices) |idx_accessor_index| {
        const idx_accessor = self.accessors[idx_accessor_index];
        const idx_view = self.buffer_views[idx_accessor.buffer_view.?];
        const idx_buffer = self.loaded_buffers[idx_view.buffer];

        const idx_offset = idx_view.byte_offset + idx_accessor.byte_offset;

        indices = try allocator.alloc(u32, idx_accessor.count);

        switch (idx_accessor.component_type) {
            5121 => {
                const src = idx_buffer[idx_offset..][0..idx_accessor.count];
                for (src, indices) |s, *d| d.* = s;
            },
            5123 => {
                const src = std.mem.bytesAsSlice(
                    u16,
                    idx_buffer[idx_offset..][0 .. idx_accessor.count * 2],
                );
                for (src, indices) |s, *d| d.* = s;
            },
            5125 => {
                const src = std.mem.bytesAsSlice(
                    u32,
                    idx_buffer[idx_offset..][0 .. idx_accessor.count * 4],
                );
                @memcpy(indices, src);
            },
            else => return error.UnsupportedIndexType,
        }
    }

    return .{
        .positions = positions,
        .indices = indices,
    };
}
