const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

pub const Vec3 = @Vector(3, f32);

pub const Axis = enum {
    x,
    y,
    z,
};

pub const Transform = struct {
    position: Vec3 = @splat(0),
    rotation: Quaternion = .identity,
    scale: Vec3 = .{ 1.0, 1.0, 1.0 },

    pub fn matrix(self: Transform) Matrix4 {
        return Matrix4.translation(self.position)
            .mul(self.rotation.matrix())
            .scaled(self.scale);
    }
};

pub const Quaternion = packed struct {
    w: f32,
    x: f32,
    y: f32,
    z: f32,

    pub const identity: Quaternion = .{
        .w = 1.0,
        .x = 0.0,
        .y = 0.0,
        .z = 0.0,
    };

    pub fn wxyz(self: Quaternion) struct { f32, f32, f32, f32 } {
        return .{ self.w, self.x, self.y, self.z };
    }

    pub fn xyzw(self: Quaternion) struct { f32, f32, f32, f32 } {
        return .{ self.x, self.y, self.z, self.w };
    }

    pub fn conjugate(self: Quaternion) Quaternion {
        return .{
            .w = self.w,
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
        };
    }

    pub fn inverse(self: *Quaternion) void {
        self.* = self.conjugate().normalized();
    }

    pub fn inversed(self: Quaternion) Quaternion {
        return self.conjugate().normalized();
    }

    pub fn fromAxisAngle(axis: Vec3, radians: f32) Quaternion {
        const half = radians * 0.5;
        const s = @sin(half);
        const c = @cos(half);

        return .{
            .w = c,
            .x = axis[0] * s,
            .y = axis[1] * s,
            .z = axis[2] * s,
        };
    }

    pub fn mul(a: Quaternion, b: Quaternion) Quaternion {
        return .{
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        };
    }

    pub fn normalized(self: Quaternion) Quaternion {
        const len = @sqrt(self.w * self.w +
            self.x * self.x +
            self.y * self.y +
            self.z * self.z);

        return .{
            .w = self.w / len,
            .x = self.x / len,
            .y = self.y / len,
            .z = self.z / len,
        };
    }

    pub fn rotatedLocal(self: Quaternion, radians: f32, axis: Axis) Quaternion {
        const q = switch (axis) {
            .x => fromAxisAngle(.{ 1, 0, 0 }, radians),
            .y => fromAxisAngle(.{ 0, 1, 0 }, radians),
            .z => fromAxisAngle(.{ 0, 0, 1 }, radians),
        };

        return self.mul(q).normalized();
    }

    pub fn rotatedWorld(self: Quaternion, radians: f32, axis: Axis) Quaternion {
        const q = switch (axis) {
            .x => fromAxisAngle(.{ 1, 0, 0 }, radians),
            .y => fromAxisAngle(.{ 0, 1, 0 }, radians),
            .z => fromAxisAngle(.{ 0, 0, 1 }, radians),
        };

        return q.mul(self).normalized();
    }

    pub fn rotateVector(self: Quaternion, v: Vec3) Vec3 {
        const q = self.normalized();

        const p: Quaternion = .{
            .w = 0.0,
            .x = v[0],
            .y = v[1],
            .z = v[2],
        };

        const result = q.mul(p).mul(q.conjugate());

        return .{
            result.x,
            result.y,
            result.z,
        };
    }

    pub fn matrix(self: Quaternion) Matrix4 {
        const q = self.normalized();

        const w, const x, const y, const z = q.wxyz();

        return .{ .inner = .{
            1 - 2 * (y * y + z * z), 2 * (x * y - z * w),     2 * (x * z + y * w),     0,
            2 * (x * y + z * w),     1 - 2 * (x * x + z * z), 2 * (y * z - x * w),     0,
            2 * (x * z - y * w),     2 * (y * z + x * w),     1 - 2 * (x * x + y * y), 0,
            0,                       0,                       0,                       1,
        } };
    }
};
pub const Matrix4 = extern struct {
    inner: [4 * 4]f32,

    pub const identity: Matrix4 = .{ .inner = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    } };

    pub fn mul(a: Matrix4, b: Matrix4) Matrix4 {
        var result: Matrix4 = .{ .inner = undefined };

        for (0..4) |col| {
            for (0..4) |row| {
                result.inner[col * 4 + row] =
                    a.inner[0 * 4 + row] * b.inner[col * 4 + 0] +
                    a.inner[1 * 4 + row] * b.inner[col * 4 + 1] +
                    a.inner[2 * 4 + row] * b.inner[col * 4 + 2] +
                    a.inner[3 * 4 + row] * b.inner[col * 4 + 3];
            }
        }

        return result;
    }

    // transformations

    pub fn translate(self: *Matrix4, v: Vec3) void {
        self.* = self.mul(.translation(v));
    }

    pub fn rotate(self: *Matrix4, radians: f32, axis: Axis) void {
        self.* = self.mul(.rotation(radians, axis));
    }

    pub fn scale(self: *Matrix4, v: Vec3) void {
        self.* = self.mul(.scale(v));
    }

    // composition

    pub fn translated(self: Matrix4, v: Vec3) Matrix4 {
        return self.mul(.translation(v));
    }

    pub fn rotated(self: Matrix4, radians: f32, axis: Axis) Matrix4 {
        return self.mul(.rotation(radians, axis));
    }

    pub fn scaled(self: Matrix4, v: Vec3) Matrix4 {
        return self.mul(.scaling(v));
    }

    // constructors

    pub fn translation(v: Vec3) Matrix4 {
        return .{ .inner = .{
            1,    0,    0,    0,
            0,    1,    0,    0,
            0,    0,    1,    0,
            v[0], v[1], v[2], 1,
        } };
    }

    pub fn rotation(radians: f32, axis: Axis) Matrix4 {
        const s = @sin(radians);
        const c = @cos(radians);

        return switch (axis) {
            .x => .{ .inner = .{
                1, 0,  0, 0,
                0, c,  s, 0,
                0, -s, c, 0,
                0, 0,  0, 1,
            } },

            .y => .{ .inner = .{
                c, 0, -s, 0,
                0, 1, 0,  0,
                s, 0, c,  0,
                0, 0, 0,  1,
            } },

            .z => .{ .inner = .{
                c,  s, 0, 0,
                -s, c, 0, 0,
                0,  0, 1, 0,
                0,  0, 0, 1,
            } },
        };
    }

    pub fn scaling(v: Vec3) Matrix4 {
        return .{ .inner = .{
            v[0], 0,    0,    0,
            0,    v[1], 0,    0,
            0,    0,    v[2], 0,
            0,    0,    0,    1,
        } };
    }

    pub fn perspectiveFovLh(fovy: f32, aspect: f32, near: f32, far: f32) Matrix4 {
        assert(near > 0.0 and far > 0.0);
        // assert(!math.approxEqAbs(f32, far, near, 0.001));
        // assert(!math.approxEqAbs(f32, aspect, 0.0, 0.01));

        const h = 1.0 / @tan(fovy * 0.5);
        const w = h / aspect;
        const r = far / (far - near);

        return .{ .inner = .{
            w, 0, 0,         0,
            0, h, 0,         0,
            0, 0, r,         1,
            0, 0, -r * near, 0,
        } };
    }
};
