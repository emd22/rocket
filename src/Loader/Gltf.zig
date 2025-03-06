const c = @import("../CLibs.zig").c;

const std = @import("std");

pub const GLTFModel = struct {
    data: ?*c.cgltf_data = null,

    const Self = @This();

    pub fn Load(self: *Self, filename: [:0]const u8) void {
        if (c.cgltf_parse_file(&.{}, filename.ptr, &(self.data)) == c.cgltf_result_success and c.cgltf_load_buffers(&.{}, self.data, filename.ptr) != c.cgltf_result_success) {
            std.debug.print("Loading failed\n", .{});
        }
    }

    pub fn Destroy(self: Self) void {
        c.cgltf_free(self.data);
    }
};
