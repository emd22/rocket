const FVector = @import("./Math/Vector.zig");
const FMatrix = @import("./Math/Matrix.zig");
const FQuaternion = @import("./Math/Quaternion.zig");

const FSimd = @import("./Math/SIMD.zig");

// Vector.zig
pub const Vec2 = FVector.Vec2;
pub const Vec3 = FVector.Vec3;
pub const Vec4 = FVector.Vec4;

pub const TVec2 = FVector.TVec2;
pub const TVec3 = FVector.TVec3;
pub const TVec4 = FVector.TVec4;

pub const TVec = FVector.TVec;

// Matrix.zig
pub const Mat4 = FMatrix.Mat4;
pub const Mat3 = FMatrix.Mat3;

pub const TQuat = FQuaternion.TQuat;
pub const Quat = FQuaternion.Quat;

const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}
