const m = @import("Vector.zig");
const q = @import("Quaternion.zig");
const Log = @import("../Log.zig");

pub const Mat4 = struct {
    v: [4]@Vector(4, f32),

    const Self = @This();

    pub fn AsTranslation(position: m.TVec3) Self {
        const x, const y, const z = position.v;

        return Self{
            .v = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ x, y, z, 1 },
            },
        };
    }

    pub fn FromQuaternion(quat: q.TQuat, translation: m.TVec3) Self {
        const m3 = Mat3.FromQuaternion(quat);

        const rr0 = m3.v[0];
        const rr1 = m3.v[1];
        const rr2 = m3.v[2];
        const trs = translation.v;

        // const zero: @Vector(4, f32) = @splat(0);

        // const r0 = @

        // const r0 = @select(f32, [4]bool{ true, true, true, false }, rr0, zero);
        // const r1 = @select(f32, [4]bool{ true, true, true, false }, rr1, zero);
        // const r2 = @select(f32, [4]bool{ true, true, true, false }, rr2, zero);
        // const r3 = @select(f32, [4]bool{ true, true, true, false }, translation, zero);

        const r0 = @Vector(4, f32){ rr0[0], rr0[1], rr0[2], 0 };
        const r1 = @Vector(4, f32){ rr1[0], rr1[1], rr1[2], 0 };
        const r2 = @Vector(4, f32){ rr2[0], rr2[1], rr2[2], 0 };
        const r3 = @Vector(4, f32){ trs[0], trs[1], trs[2], 1 };

        return Self{
            .v = .{ r0, r1, r2, r3 },
        };
    }

    pub fn Print(mat: *Mat4) void {
        Log.ThreadSafe = false;
        defer Log.ThreadSafe = true;

        // better to do our own mutex operations here to avoid
        // constantly locking/unlocking
        const log_mutex = Log.GetMutex();

        log_mutex.lock();
        defer log_mutex.unlock();

        inline for (0..4) |i| {
            const vec = mat.v[i];
            Log.WriteRaw("[ {d: >10.6} {d: >10.6} {d: >10.6} {d: >10.6} ]\n", .{ vec[0], vec[1], vec[2], vec[3] });
        }
    }

    pub inline fn MulAdd(v0: anytype, v1: anytype, v2: anytype) @TypeOf(v0, v1, v2) {
        return @mulAdd(@TypeOf(v0, v1, v2), v0, v1, v2);
    }

    // pub inline fn UpdateFromTransforms(self: *Self, unit_quat: q.Quat, translate_vec: m.TVec3) void {

    // }

    pub fn Multiply(self: Self, other: Self) Self {
        var result = Self{ .v = std.mem.zeroes([4]@Vector(4, f32)) };
        inline for (0..4) |i| {
            const row = self.v[i];
            const vx: @Vector(4, f32) = @splat(row[0]);
            const vy: @Vector(4, f32) = @splat(row[1]);
            const vz: @Vector(4, f32) = @splat(row[2]);
            const vw: @Vector(4, f32) = @splat(row[3]);

            result.v[i] =
                MulAdd(vx, other.v[0], vz * other.v[2]) +
                MulAdd(vy, other.v[1], vw * other.v[3]);
        }
        return result;
    }

    pub fn Identity() Self {
        return Self{
            .v = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn Perspective(hfov: f32, aspect: f32, near: f32, far: f32) Self {
        const S = 1.0 / (@tan(hfov * 0.5));

        return Self{
            .v = .{
                .{ S / aspect, 0, 0, 0 },
                .{ 0, S, 0, 0 },
                .{ 0, 0, -(far + near) / (far - near), -1 },
                .{ 0, 0, -(2.0 * far * near) / (far - near), 0 },
            },
        };
    }

    pub fn LookAtColMajor(eyePos: m.TVec3, eyeTarget: m.TVec3, eyeUp: m.TVec3) Self {
        const target_to_position = m.TVec3{ .v = eyePos.v - eyeTarget.v };
        const a = target_to_position.Normalized();
        const b = m.TVec3.Normalized(m.TVec3.Cross(eyeUp, a));
        const c = a.Cross(b);

        return Self{
            .v = .{
                .{ b.v[0], c.v[0], a.v[0], 0 },
                .{ b.v[1], c.v[1], a.v[1], 0 },
                .{ b.v[2], c.v[2], a.v[2], 0 },
                .{ -b.Dot(eyePos), -c.Dot(eyePos), -a.Dot(eyePos), 1 },
            },
        };
    }

    pub fn Transpose(self: Self) Self {
        const temp1 = @shuffle(f32, self.v[0], self.v[1], [4]i32{ 0, 1, ~@as(i32, 0), ~@as(i32, 1) });
        const temp3 = @shuffle(f32, self.v[0], self.v[1], [4]i32{ 2, 3, ~@as(i32, 2), ~@as(i32, 3) });
        const temp2 = @shuffle(f32, self.v[2], self.v[3], [4]i32{ 0, 1, ~@as(i32, 0), ~@as(i32, 1) });
        const temp4 = @shuffle(f32, self.v[2], self.v[3], [4]i32{ 2, 3, ~@as(i32, 2), ~@as(i32, 3) });

        return Self{
            .v = .{
                @shuffle(f32, temp1, temp2, [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) }),
                @shuffle(f32, temp1, temp2, [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) }),
                @shuffle(f32, temp3, temp4, [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) }),
                @shuffle(f32, temp3, temp4, [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) }),
            },
        };
    }

    pub fn MakeRotation(components: m.TVec3, angle: f32) Mat4 {
        const s = @sin(angle);
        const c = @cos(angle);

        const i = 1.0 - c;

        const x, const y, const z = components.v;

        const value = Self{
            .v = .{
                .{ i * x * x + c, i * x * y - z * s, i * z * x + y * s, 0.0 },
                .{ i * x * y + z * s, i * y * y + c, i * y * z - x * s, 0.0 },
                .{ i * z * x - y * s, i * y * z + x * s, i * z * z + c, 0.0 },
                .{ 0.0, 0.0, 0.0, 1.0 },
            },
        };

        return value;
    }

    pub fn RotationX(rad: f32) Self {
        const rcos = @cos(rad);
        const rsin = @sin(rad);

        return Self{
            .v = .{
                .{ 1, 0, 0, 0 },
                .{ 0, rcos, rsin, 0 },
                .{ 0, -rsin, rcos, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn RotationY(rad: f32) Self {
        const rcos = @cos(rad);
        const rsin = @sin(rad);

        return Self{
            .v = .{
                .{ rcos, 0, -rsin, 0 },
                .{ 0, 0, 0, 0 },
                .{ rsin, 0, rcos, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn RotationZ(rad: f32) Self {
        const rcos = @cos(rad);
        const rsin = @sin(rad);

        return Self{
            .v = .{
                .{ rcos, rsin, 0, 0 },
                .{ -rsin, rcos, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn Equals(self: Self, other: Self) bool {
        return std.meta.eql(self.v, other.v);
    }
};

pub const Mat3 = struct {
    const RowType = @Vector(3, f32);

    v: [3]RowType,

    const Self = @This();

    pub fn AsTranslation(position: m.TVec3) Self {
        return Self{
            .v = .{
                .{ 1, 0, 0 },
                .{ 0, 1, 0 },
                position,
            },
        };
    }

    pub fn Print(mat: *Self) void {
        Log.ThreadSafe = false;
        defer Log.ThreadSafe = true;

        // better to do our own mutex operations here to avoid
        // constantly locking/unlocking
        const log_mutex = Log.GetMutex();

        log_mutex.lock();
        defer log_mutex.unlock();

        inline for (0..3) |i| {
            const vec = mat.v[i];
            // fill with [ ](space), align right with column of size 10, maximum 6 decimal points
            Log.WriteRaw("[ {d: >10.6} {d: >10.6} {d: >10.6} ]\n", .{ vec[0], vec[1], vec[2] });
        }
    }

    pub inline fn MulAdd(v0: anytype, v1: anytype, v2: anytype) @TypeOf(v0, v1, v2) {
        return @mulAdd(@TypeOf(v0, v1, v2), v0, v1, v2);
    }

    // pub inline fn UpdateFromTransforms(self: *Self, unit_quat: q.Quat, translate_vec: m.TVec3) void {

    // }
    //

    // pub fn FromQuaternion0(quat: q.TQuat) Mat3 {
    //     const qv = quat.v;

    //     const xx = qv[1] * qv[1];
    //     const yy = qv[2] * qv[2];
    //     const zz = qv[3] * qv[3];

    //     const xy = qv[1] * qv[2];
    //     const xz = qv[1] * qv[3];
    //     const yz = qv[2] * qv[3];

    //     const xw = qv[1] * qv[0];
    //     const yw = qv[2] * qv[0];
    //     const zw = qv[3] * qv[0];

    //     return Mat3{
    //         .v = .{
    //             .{
    //                 // 1 - 2yy - 2zz
    //                 1.0 - 2.0 * (yy + zz),
    //                 // 2 * qx * qy - 2 * qz * qw
    //                 2.0 * (xy - zw),
    //                 2.0 * (xz + yw),
    //             },
    //             .{
    //                 2.0 * (xy + zw),
    //                 1.0 - 2.0 * (xx + zz),
    //                 2.0 * (yz - xw),
    //             },
    //             .{
    //                 2.0 * (xz - yw),
    //                 2.0 * (yz + xw),
    //                 1.0 - 2.0 * (xx + yy),
    //             },
    //         },
    //     };
    // }

    pub fn FromQuaternion(quat: q.TQuat) Mat3 {
        const q2 = quat.v * quat.v;
        const wv = @as(@Vector(4, f32), @splat(quat.v[0])) * quat.v;

        // a: w x x y
        // b: w y z z

        const alt = @shuffle(f32, quat.v, undefined, [4]i32{ 0, 1, 1, 2 }) * @shuffle(f32, quat.v, undefined, [4]i32{ 0, 2, 3, 3 });

        return Mat3{
            .v = .{
                .{
                    // 1 - 2yy - 2zz
                    1.0 - 2.0 * (q2[2] + q2[3]),
                    // 2 * qx * qy - 2 * qz * qw
                    2.0 * (alt[1] - wv[3]),
                    2.0 * (alt[2] + wv[2]),
                },
                .{
                    2.0 * (alt[1] + wv[3]),
                    1.0 - 2.0 * (q2[1] + q2[3]),
                    2.0 * (alt[3] - wv[1]),
                },
                .{
                    2.0 * (alt[2] - wv[2]),
                    2.0 * (alt[3] + wv[1]),
                    1.0 - 2.0 * (q2[1] + q2[2]),
                },
            },
        };
    }

    pub fn Identity() Self {
        return Self{
            .v = .{
                .{ 1, 0, 0 },
                .{ 0, 1, 0 },
                .{ 0, 0, 1 },
            },
        };
    }

    pub fn Equals(self: Self, other: Self) bool {
        return std.meta.eql(self.v, other.v);
    }
};

const std = @import("std");

const debug = std.debug;
const testing = std.testing;
const assert = debug.assert;

test "make translation" {
    var mat = Mat4.AsTranslation(m.Vec3(1, 2, 3));
    Log.Debug("Translation test: ", .{});
    mat.Print();
}

test "matrix multiply" {
    const a = Mat4{
        .v = .{
            .{ 1, 0, 4, -6 },
            .{ 2, 5, 0, 3 },
            .{ -1, 2, 3, 5 },
            .{ 2, 1, -2, 3 },
        },
    };
    var c = a.Multiply(a);

    Log.Debug("Fast multiply: ", .{});

    c.Print();

    const expected = Mat4{
        .v = .{
            .{ -15, 2, 28, -4 },
            .{ 18, 28, 2, 12 },
            .{ 10, 21, -5, 42 },
            .{ 12, 4, -4, -10 },
        },
    };

    try testing.expect(c.Equals(expected));
}

test "matrix3 from quaternion" {
    var quat = q.Quat(0.7071, 0.0, 0.7071, 0.0);
    quat.Normalized();
    var mat = Mat3.FromQuaternion0(quat);
    Log.Debug("Matrix from quaternion: ", .{});
    mat.Print();
    std.debug.print("\n", .{});
}

// 1 0 4 -6
// 2 5 0 3
// -1 2 3 5
// 2 1 -2 3
