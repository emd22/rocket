const Log = @import("../Log.zig");

const m = @import("Matrix.zig");
const q = @import("Quaternion.zig");

pub const TVec2 = TVec(@Vector(2, f32));
pub const TVec3 = TVec(@Vector(3, f32));
pub const TVec4 = TVec(@Vector(4, f32));

pub inline fn Vec2(x: f32, y: f32) TVec2 {
    return TVec2{ .v = .{ x, y } };
}

pub inline fn Vec3(x: f32, y: f32, z: f32) TVec3 {
    return TVec3{ .v = .{ x, y, z } };
}

pub inline fn Vec4(x: f32, y: f32, z: f32, w: f32) TVec4 {
    return TVec4{ .v = .{ x, y, z, w } };
}

pub fn Vec4Swizzle(
    vec: @Vector(4, f32),
    comptime x: TVec4.Component,
    comptime y: TVec4.Component,
    comptime z: TVec4.Component,
    comptime w: TVec4.Component,
) @Vector(4, f32) {
    return @shuffle(f32, vec, undefined, [4]i32{
        @intFromEnum(x),
        @intFromEnum(y),
        @intFromEnum(z),
        @intFromEnum(w),
    });
}

/// The base struct for creating vector types
pub fn TVec(comptime T: type) type {
    const ElementType = @typeInfo(T).Vector.child;
    const TLen = @typeInfo(T).Vector.len;

    return struct {
        const Self = @This();

        /// The type of the internal SIMD vector
        pub const Type = T;

        /// internal SIMD vector type for direct manipulation
        v: T = @splat(0),

        /// The named components of a vector (X, Y, Z, W)
        pub const Component = switch (TLen) {
            2 => enum { X, Y },
            3 => enum { X, Y, Z },
            4 => enum { X, Y, Z, W },
            else => {},
        };

        pub const Zero = Self{ .v = @splat(0) };

        /// Retrieve the X component of the vector.
        pub inline fn GetX(self: Self) ElementType {
            return self.v[0];
        }

        /// Retrieve the Y component of the vector.
        pub inline fn GetY(self: Self) ElementType {
            return self.v[1];
        }

        /// Retrieve the Z component of the vector.
        pub inline fn GetZ(self: Self) ElementType {
            if (comptime TLen < 3) {
                @compileError("Type does not contain Z component");
            }
            return self.v[2];
        }

        /// Retrieve the W component of the vector.
        pub inline fn GetW(self: Self) ElementType {
            if (comptime TLen < 4) {
                @compileError("Type does not contain W component");
            }

            return self.v[3];
        }

        pub inline fn Sin(self: Self) Self {
            return Self{
                .v = @sin(self.v),
            };
        }

        pub inline fn Cos(self: Self) Self {
            return Self{
                .v = @sin(self.v),
            };
        }

        pub inline fn Equals(self: Self, other: Self) bool {
            return std.meta.eql(self.v, other.v);
        }

        pub fn Length(self: Self) f32 {
            return @sqrt(@reduce(.Add, self.v * self.v));
        }

        pub inline fn Normalize(self: Self) Self {
            return Self{
                .v = self.v / @as(T, @splat(self.Length())),
            };
        }

        pub inline fn Add(self: Self, other: Self) Self {
            return Self{ .v = self.v + other.v };
        }

        pub inline fn Subtract(self: Self, other: Self) Self {
            return Self{ .v = self.v - other.v };
        }

        pub inline fn Divide(self: Self, other: Self) Self {
            return Self{ .v = self.v / other.v };
        }

        pub inline fn Multiply(self: Self, other: Self) Self {
            return Self{ .v = self.v * other.v };
        }

        pub inline fn Dot(self: Self, other: Self) ElementType {
            return @reduce(.Add, self.v * other.v);
        }

        /// Log out the vector data using the Log system.
        pub fn Print(self: Self) void {
            Log.ThreadSafe = false;
            defer Log.ThreadSafe = true;

            const log_mutex = Log.GetMutex();
            log_mutex.lock();
            defer log_mutex.unlock();

            Log.WriteChar('{');

            inline for (0..TLen) |i| {
                Log.WriteRaw("{d}", .{self.v[i]});

                if (i < TLen - 1) {
                    Log.WriteRaw(", ", .{});
                }
            }

            Log.WriteChar('}');
            Log.WriteChar('\n');
        }

        ///////////////////////////////
        // Vector3 Functions
        ///////////////////////////////

        pub fn Cross(self: Self, other: Self) Self {
            if (comptime TLen != 3) {
                @compileError("Cannot use cross on non-vec3 type");
            }

            const ax, const ay, const az = self.v;
            const bx, const by, const bz = other.v;

            return Self{
                .v = .{
                    ay * bz - by * az,
                    -(ax * bz - bx * az),
                    ax * by - bx * ay,
                },
            };
        }

        pub fn RotateQuat(self: *Self, quat: q.TQuat) void {
            if (comptime TLen != 3) {
                @compileError("Expected a Vector3 type");
            }

            const q_vec = q.Quat(0, self.v[0], self.v[1], self.v[2]);

            const q_conj = quat.Conjugate();
            var q_result = quat.MultipliedBy(q_vec);
            q_result.Multiply(q_conj);

            // return Self{
            self.v = @Vector(3, f32){ q_result.v[1], q_result.v[2], q_result.v[3] };
            // };
            // const u = Vec3(quat.v[1], quat.v[2], quat.v[3]);
            // const s: T = @splat(quat.v[0] * quat.v[0]);

            // const v2: T = @splat(2);

            // const res = (v2 * @as(T, @splat(Dot(u, self.*))) * u.v) + ((s - @as(T, @splat(Dot(u, u)))) * self.v) + (v2 * s * Cross(u, self.*).v);
            // self.v = res;
        }

        pub fn MultiplyMat3(self: *Self, matrix: m.Mat3) void {
            if (comptime TLen != 3) {
                @compileError("Expected a Vector3 type");
            }

            const xxx: T = @splat(self.v[0]);
            const yyy: T = @splat(self.v[1]);
            const zzz: T = @splat(self.v[2]);

            // r0 = row 0 * vx
            // r1 = row 1 * vy + r0
            // result = row 2 * vz + r1

            var result = matrix.v[0] * xxx;
            result = @mulAdd(T, yyy, matrix.v[1], result);
            self.v = @mulAdd(T, zzz, matrix.v[2], result);
        }

        pub inline fn MultipliedByMat3(self: Self, matrix: m.Mat3) m.TVec3 {
            var copy = self;
            copy.MultiplyVec(matrix);
            return copy;
        }

        ///////////////////////////////
        // Vector4 Functions
        ///////////////////////////////

        pub fn Swizzle(
            self: Self,
            comptime x: Component,
            comptime y: Component,
            comptime z: Component,
            comptime w: Component,
        ) Self {
            if (comptime TLen != 4) {
                @compileError("Expected Vector4 type");
            }

            return Vec4Swizzle(self.v, x, y, z, w);
        }
    };
}

const std = @import("std");

const debug = std.debug;
const testing = std.testing;
const assert = debug.assert;

test "cross product of two vectors" {
    const a = Vec3(1, 2, 3);
    const b = Vec3(4, 5, 6);
    const c = a.Cross(b);

    c.Print();

    const expected = Vec3(-3, 6, -3);

    try testing.expect(c.Equals(expected));
}

test "make vector3" {
    const a = Vec3(1, 2, 3);
    try testing.expect(a.v[0] == 1 and a.v[1] == 2 and a.v[2] == 3);
}

test "make vector4" {
    const a = Vec4(1, 2, 3, 4);
    try testing.expect(a.v[0] == 1 and a.v[1] == 2 and a.v[2] == 3 and a.v[3] == 4);
}
