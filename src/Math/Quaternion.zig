const m = @import("Vector.zig");
const std = @import("std");

const Log = @import("../Log.zig");

pub inline fn Quat(w: f32, x: f32, y: f32, z: f32) TQuat {
    return TQuat{ .v = .{ w, x, y, z } };
}

pub const TQuat = TQuaternion(f32);

pub fn TQuaternion(comptime T: type) type {
    return struct {
        const Self = @This();

        /// quaternion is stored as {W, X, Y, Z}
        const VType = @Vector(4, T);

        v: VType,

        pub inline fn Identity() Self {
            return Self{
                .v = .{ 1.0, 0.0, 0.0, 0.0 },
            };
        }

        pub fn FromVec3(w: T, axis: *m.TVec3) Self {
            return Self{
                .v = .{ w, axis.v[0], axis.v[1], axis.v[2] },
            };
        }

        pub inline fn Normalize(self: *Self) void {
            // values *= invsqrt(w^2 + x^2 + y^2 + z^2)
            const vsqr = self.v * self.v;
            const sq = @sqrt(@reduce(.Add, vsqr));

            if (sq > 0.0) {
                self.v *= @splat(1.0 / sq);
            } else {
                self.* = Identity();
            }
        }

        pub inline fn Normalized(self: Self) Self {
            const vsqr = self.v * self.v;
            const sq = @sqrt(@reduce(.Add, vsqr));

            return Self{ .v = self.v * @as(VType, @splat((1.0 / sq))) };
        }

        pub inline fn Conjugate(self: Self) Self {
            return Self{ .v = @shuffle(f32, -self.v, self.v, [4]i32{ -1, 1, 2, 3 }) };
        }

        pub inline fn Inverse(self: Self) Self {
            const vsqr = self.v * self.v;
            const len = @reduce(.Add, vsqr);

            if (len == 0) {
                return Identity();
            }

            return Conjugate(self.v) / len;
        }

        pub fn MultipliedSlow(self: Self, other: Self) Self {
            return Self{
                .v = .{
                    self.v[0] * other.v[0] - self.v[1] * other.v[1] - self.v[2] * other.v[2] - self.v[3] * other.v[3],
                    self.v[0] * other.v[1] + self.v[1] * other.v[0] + self.v[2] * other.v[3] - self.v[3] * other.v[2],
                    self.v[0] * other.v[2] - self.v[1] * other.v[3] + self.v[2] * other.v[0] + self.v[3] * other.v[1],
                    self.v[0] * other.v[3] + self.v[1] * other.v[2] - self.v[2] * other.v[1] + self.v[3] * other.v[0],
                },
            };
        }

        /// Return the product of two quaternions as a new quaternion
        pub inline fn MultipliedBy(self: Self, other: Self) Self {
            var copy = self;
            copy.Multiply(other);
            return copy;
        }

        /// Multiply the quaternion in place with another quaternion
        pub inline fn Multiply(self: *Self, other: Self) void {
            const bv = other.v;
            const negbv = -other.v;

            // for each column of the operation, swizzle, sum, and flip sign to get the final column value.
            // Afterwards, we can sum all of the columns to get the final quaternion.
            //
            // here is the idea behind the vector values:
            //
            //   c0 =   a.wwww * b.wxyz * {  1,  1,  1,  1 }
            //   c1 =   a.xxxx * b.xwzy * { -1,  1, -1,  1 }
            //   c2 =   a.yyyy * b.yzwx * { -1,  1,  1, -1 }
            //   c3 =   a.zzzz * b.zyxw * { -1, -1,  1,  1 }

            // +w +x +y +z
            const c0 = @as(VType, @splat(self.v[0])) * other.v;
            // -x +w -z +y
            const c1 = @as(VType, @splat(self.v[1])) * @shuffle(T, bv, negbv, [4]i32{ -2, 0, -4, 2 });
            // -y +z +w -x
            const c2 = @as(VType, @splat(self.v[2])) * @shuffle(T, bv, negbv, [4]i32{ -3, 3, 0, -2 });
            // -z -y +x +w
            const c3 = @as(VType, @splat(self.v[3])) * @shuffle(T, bv, negbv, [4]i32{ -4, -3, 1, 0 });

            self.v = c0 + c1 + c2 + c3;
        }

        // Warning: Different order than TVec4!
        pub const Component = enum { W, X, Y, Z };

        /// Create a rotation quaternion from the given angle for the components provided
        /// Usage:
        /// ```zig
        /// const rotation = TQuat.FromRotation(0.23, &.{.X, .Y});
        /// const product = my_other_quat.Multiply(rotation);
        /// ```
        pub inline fn FromRotation(comptime components: []const Component, angle: T) Self {
            const half_angle: T = angle * 0.5;

            // TODO: replace with custom a custom SinCos function
            const sin_values: VType = @splat(@sin(half_angle));
            const cos_values: VType = @splat(@cos(half_angle));

            // generate the component mask in comptime.
            // &.{.X} -> {0, 1, 0, 0}, &.{.X, .Y} = {0, 1, 1, 0}, etc.
            comptime var vmask: @Vector(4, f32) = .{ 0, 0, 0, 0 };
            comptime for (components) |elem| {
                vmask[@intFromEnum(elem)] = 1;
            };

            // Log.WriteRaw("mask: {d} {d} {d} {d}\n", .{ vmask[0], vmask[1], vmask[2], vmask[3] });

            const prod = vmask * sin_values;

            const result = @select(T, [4]bool{ true, false, false, false }, cos_values, prod);

            return Self{ .v = result };
        }

        pub inline fn Rotate(self: *Self, comptime components: []const Component, angle: T) void {
            const xform_quat = FromRotation(components, angle);
            self.* = xform_quat.MultipliedSlow(self.*);
        }

        pub fn Print(self: Self) void {
            Log.WriteRaw("{{ W:{d}, X:{d}, Y:{d}, Z:{d} }}\n", .{ self.v[0], self.v[1], self.v[2], self.v[3] });
        }

        pub inline fn Equals(self: Self, other: Self) bool {
            return std.meta.eql(self.v, other.v);
        }
    };
}

const debug = std.debug;
const testing = std.testing;
const assert = debug.assert;

test "multiply" {
    const a = TQuat{ .v = .{ 1, 2, 3, 4 } };
    const b = TQuat{ .v = .{ 6, 7, 8, 9 } };
    const c = a.MultipliedBy(b);
    const d = a.MultipliedSlow(b);

    Log.WriteRaw("\n=== Mult quaternion ===\n", .{});
    c.Print();
    Log.WriteRaw("\n=== Mult quaternion 2 ===\n", .{});
    d.Print();

    try testing.expect(c.Equals(d));
}

test "from rotation" {
    const rot = TQuat.FromRotation(&.{.X}, 0.24);
    rot.Print();
}

test "rotate quaternion" {
    var a = Quat(0.18, 0.36, 0.54, 0.73);
    a.Rotate(&.{.X}, 0.24);
    a.Print();
}
