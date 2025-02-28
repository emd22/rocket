const std = @import("std");

const BufferItem = struct {
    pub const Type = enum {
        GPU_BUFFER,
    };

    type: Type,
    data: *anyopaque,
};

var allocator = std.Allocator{};
var gpa: @TypeOf(std.heap.GeneralPurposeAllocator(.{}){}) = undefined;

pub fn startThread(self: *DataHandler) std.Thread.SpawnError!void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();

    self.thread = try std.Thread.spawn(self.threadMain);
}

pub const DataHandler = struct {
    active: bool = true,
    transferMutex: std.Thread.Mutex = std.Thread.Mutex{},
    thread: std.Thread = undefined,
    queue: @TypeOf(std.ArrayList(BufferItem)) = std.ArrayList(BufferItem),

    pub fn destroy(self: *DataHandler) void {
        self.queue.deinit();
    }

    pub fn uploadToGPUBuffer(self: *DataHandler, data: *anyopaque) void {
        const item = BufferItem{
            .type = BufferItem.Type.GPU_BUFFER,
            .data = data,
        };
        self.queue.append(item);
    }

    pub fn threadMain(self: *DataHandler) !void {
        while (self.active) {}
    }
};
