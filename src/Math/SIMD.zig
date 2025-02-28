pub const m = @import("Matrix.zig");

const std = @import("std");

// Constants
// const c_minus_cephes_DP1 = -0.78515625;
// const c_minus_cephes_DP2 = -2.4187564849853515625e-4;
// const c_minus_cephes_DP3 = -3.77489497744594108e-8;
// const c_sincof_p0 = -1.9515295891E-4;
// const c_sincof_p1 = 8.3321608736E-3;
// const c_sincof_p2 = -1.6666654611E-1;
// const c_coscof_p0 = 2.443315711809948E-005;
// const c_coscof_p1 = -1.388731625493765E-003;
// const c_coscof_p2 = 4.166664568298827E-002;
// const c_cephes_FOPI = 1.27323954473516; // 4 / M_PI

// const v4sf = @Vector(4, f32);
// const v4su = @Vector(4, u32);

// inline fn VecTest(a: v4su, b: v4su) v4su {
//     return @intFromBool((a & b) != @as(@Vector(4, u32), @splat(0)));
// }

// inline fn vbslq_f32(mask: v4su, a: v4sf, b: v4sf) v4sf {
//     return @select(f32, mask != @as(@Vector(4, u32), @splat(0)), a, b);
// }

const FType = @Vector(4, f32);
const UType = @Vector(4, u32);

// cephes sinf function
// adapted from http://gruntthepeon.free.fr/ssemath/neon_mathfun.h

// pub fn sincos_ps(x: v4sf, ysin: *v4sf, ycos: *v4sf) callconv(.C) void {
//     // vcltq_f32
//     var sign_mask_sin: v4su = @intFromBool(x < @as(FType, @splat(0.0)));
//     const x_abs = @abs(x);

//     // scale X by 4/Pi
//     const x_fopi = x_abs * @as(FType, @splat(c_cephes_FOPI));

//     const all_ones = v4su{ 1, 1, 1, 1 };

//     // store the integer part of y in emm2
//     const emm2: UType = (@as(UType, @intFromFloat(x_fopi)) + all_ones) & ~all_ones;

//     const y: FType = @floatFromInt(emm2);

//     // polynomial selection mask
//     const poly_mask = VecTest(emm2, @splat(2));

//     const polyx = x_abs + (y * @as(FType, @splat(c_minus_cephes_DP1))) + (y * @as(FType, @splat(c_minus_cephes_DP2))) + (y * @as(FType, @splat(c_minus_cephes_DP3)));

//     // evaluate the polynomials
//     const z = (polyx * polyx);

//     // ((((z * c_coscof_p0) + c_coscof_p1) * z + c_coscof_p2) * z * z) - (z * 0.5) + 1
//     const zsqr = z * z;

//     const scos_p0 = zsqr * @as(FType, @splat(c_coscof_p0));
//     const scos_p1 = z * @as(FType, @splat(c_coscof_p1));
//     const scos_p2 = @as(FType, @splat(c_coscof_p2));

//     const half_vec = -z * v4sf{ 0.5, 0.5, 0.5, 0.5 };

//     const y1 = (scos_p0 + scos_p1 + scos_p2) * zsqr + (half_vec) + @as(v4sf, @splat(1));

//     const ssin_p0 = zsqr * @as(FType, @splat(c_sincof_p0));
//     const ssin_p1 = z * @as(FType, @splat(c_sincof_p1));
//     const ssin_p2 = @as(FType, @splat(c_sincof_p2));

//     // (((z * c_sincof_p0 + c_sincof_p1) * z + c_sincof_p2) * z * polyx) + polyx
//     // (((z^2 * c_sincof_p0 + z * c_sincof_p1) + c_sincof_p2) * z * polyx) + polyx
//     const y2 = (ssin_p0 + ssin_p1 + ssin_p2) * z * polyx + polyx;

//     // select the correct result from the two polynomials
//     const ys = vbslq_f32(poly_mask, y1, y2);
//     const yc = vbslq_f32(poly_mask, y2, y1);

//     sign_mask_sin = sign_mask_sin ^ VecTest(emm2, @splat(4));
//     const sign_mask_cos = VecTest(emm2 - @as(@Vector(4, u32), @splat(2)), @splat(4));
//     ysin.* = vbslq_f32(sign_mask_sin, -ys, ys);
//     ycos.* = vbslq_f32(sign_mask_cos, yc, -yc);
// }

// test "sine and cosine" {
//     var ysin: v4sf = undefined;
//     var ycos: v4sf = undefined;

//     const x = @Vector(4, f32){ 1.0, 2.0, 3.0, 4.0 };

//     sincos_ps(x, &ysin, &ycos);
//     std.debug.print("sin0: {}\n", .{ysin});
//     std.debug.print("cos0: {}\n\n", .{ycos});

//     std.debug.print("sin1: {}\n", .{@sin(x)});
//     std.debug.print("cos1: {}\n", .{@cos(x)});
// }
//

pub fn MultiplyVec3ByMat3(comptime T: type, self: *@Vector(3, T), matrix: m.Mat3) void {
    const VecType = @Vector(3, T);

    const xxx: VecType = @splat(self.v[0]);
    const yyy: VecType = @splat(self.v[1]);
    const zzz: VecType = @splat(self.v[2]);

    // r0 = row 0 * vx
    // r1 = row 1 * vy + r0
    // result = row 2 * vz + r1

    var result = matrix.v[0] * xxx;
    result = @mulAdd(VecType, yyy, matrix.v[1], result);
    self.* = @mulAdd(VecType, zzz, matrix.v[2], result);
}
