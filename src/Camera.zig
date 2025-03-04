const m = @import("Math.zig");

const Renderer = @import("Renderer.zig");

const std = @import("std");

const CameraPerspectiveOptions = struct {
    Near: f32 = 0.01,
    Far: f32 = 100.0,
    Fov: f32 = 80.0,
    AspectRatio: f32,
};

const BaseCamera = struct {
    Position: m.TVec3 = m.TVec3.Zero,
    Rotation: m.TQuat = m.TQuat.Identity(),

    ViewMatrix: m.Mat4 = m.Mat4.Identity(),
    ProjectionMatrix: m.Mat4 = m.Mat4.Identity(),

    const Self = @This();
};

pub fn PerspectiveCamera(options: CameraPerspectiveOptions) type {
    return struct {
        Camera: BaseCamera = .{
            .ProjectionMatrix = m.Mat4.Perspective(
                options.Fov * (std.math.pi / 180.0),
                options.AspectRatio,
                options.Near,
                options.Far,
            ),
        },

        NeedsUpdate: bool = false,
        AngleX: f32 = 0,
        AngleY: f32 = 0,

        Direction: m.TVec3 = m.TVec3.Zero,

        const Self = @This();

        pub fn UpdateProjectionMatrix(self: *Self, settings: CameraPerspectiveOptions) void {
            self.Camera.ProjectionMatrix = m.Mat4.Perspective(
                settings.Fov * (std.math.pi / 180.0),
                settings.AspectRatio,
                settings.Near,
                settings.Far,
            );

            self.NeedsUpdate = true;
            self.Update();
        }

        pub inline fn Move(self: *Self, offset: m.TVec3) void {
            // var rotated_offset = offset;

            const forward_vector = -self.Direction.v * @as(m.TVec3.Type, @splat(offset.Z()));
            const right_vector = self.Direction.Cross(m.TVec3.Up).v * @as(m.TVec3.Type, @splat(offset.X()));

            self.Camera.Position.v += (forward_vector + right_vector);

            self.NeedsUpdate = true;
        }

        pub fn Rotate(self: *Self, by: m.TVec3) void {
            self.AngleX += by.X();
            self.AngleY += by.Y();
        }

        pub inline fn MoveAxis(self: *Self, axis: m.TVec3.Component, by: f32) void {
            self.Camera.Position.v[@intFromEnum(axis)] += by;
            self.NeedsUpdate = true;
        }

        pub fn Update(self: *Self) void {
            if (!self.NeedsUpdate) {
                return;
            }

            self.Direction = m.Vec3(@sin(self.AngleX), self.AngleY, @cos(self.AngleX));
            self.Direction.Normalize();
            const target = self.Camera.Position.Subtract(self.Direction);

            self.Camera.ViewMatrix = m.Mat4.LookAtColMajor(self.Camera.Position, target, m.TVec3.Up);

            self.NeedsUpdate = false;
        }

        pub inline fn GetVPMatrix(self: Self) m.Mat4 {
            return self.Camera.ViewMatrix.Multiply(self.Camera.ProjectionMatrix);
        }
    };
}
