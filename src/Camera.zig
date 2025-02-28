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
                options.Fov * std.math.pi / 180.0,
                options.AspectRatio,
                options.Near,
                options.Far,
            ),
        },

        NeedsUpdate: bool = false,
        AngleX: f32 = 0,
        AngleY: f32 = 0,

        const Self = @This();

        pub fn UpdateProjectionMatrix(self: *Self, settings: CameraPerspectiveOptions) void {
            self.Camera.ProjectionMatrix = m.Mat4.Perspective(
                settings.Fov * std.math.pi / 180.0,
                settings.AspectRatio,
                settings.Near,
                settings.Far,
            );

            self.NeedsUpdate = true;
            self.Update();
        }

        pub inline fn Move(self: *Self, offset: m.TVec3) void {
            var rotated_offset = offset;
            // var quat = self.Camera.Rotation
            // const rotation_matrix = m.Mat3.FromQuaternion(self.Camera.Rotation);
            // const rotation_matrix = m.Mat4.FromQuaternion(self.Camera.Rotation, m.Vec3(0, 0, 0));

            // rotated_offset.MultiplyMat3(rotation_matrix);
            rotated_offset.RotateQuat(self.Camera.Rotation);
            // quat.v[3] = 0;

            // rotated_offset.RotateQuat(quat);
            // const off = offset.v * rotated_offset.v;
            self.Camera.Position.v += rotated_offset.v;

            self.NeedsUpdate = true;
        }

        pub fn Rotate(self: *Self, by: m.TVec3) void {
            // var quat = m.TQuat.Identity();

            self.AngleX += by.v[0];
            self.AngleY += by.v[1];

            // camera yaw
            const yaw = m.TQuat.FromRotation(&.{.X}, self.AngleY);
            // camera pitch(and the output quat)
            var pitch = m.TQuat.FromRotation(&.{.Y}, self.AngleX);

            // multiply pitch * yaw
            pitch.Multiply(yaw);

            pitch.Normalize();

            self.Camera.Rotation = pitch;
            // self.Camera.Rotation;
        }

        pub inline fn MoveAxis(self: *Self, axis: m.TVec3.Component, by: f32) void {
            self.Camera.Position.v[@intFromEnum(axis)] += by;
            self.NeedsUpdate = true;
        }

        pub fn Update(self: *Self) void {
            if (!self.NeedsUpdate) {
                return;
            }

            const rotation = m.Mat4.FromQuaternion(self.Camera.Rotation, m.Vec3(0, 0, 0));

            // Multiply the translation matrix with the rotation matrix
            // TODO: optimize this to multiply the quaternion directly with the matrix.
            self.Camera.ViewMatrix = m.Mat4.AsTranslation(self.Camera.Position).Multiply(rotation);

            self.NeedsUpdate = false;
        }

        pub inline fn GetVPMatrix(self: Self) m.Mat4 {
            return self.Camera.ViewMatrix.Multiply(self.Camera.ProjectionMatrix);
        }
    };
}
