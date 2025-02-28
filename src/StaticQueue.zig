//! A non-resizable queue for pushing and popping off of.

const std = @import("std");

const debug = std.debug;
const testing = std.testing;
const assert = debug.assert;

pub const StaticQueueError = error{
    QueueFull,
    QueueEmpty,
};

pub fn StaticQueue(comptime T: type, comptime queue_size: u16) type {
    return struct {
        const Self = @This();

        items: [queue_size]T = std.mem.zeroes([queue_size]T),
        item_used_map: std.StaticBitSet(queue_size) = std.StaticBitSet(queue_size).initEmpty(),
        push_index: u16 = 0,
        pop_index: u16 = 0,

        /// Push a new value into the next open position of the queue.
        pub fn Push(self: *Self, item: T) StaticQueueError!void {
            const ptr = &self.items[self.push_index];
            if (self.item_used_map.isSet(self.push_index)) {
                return StaticQueueError.QueueFull;
            }

            self.item_used_map.set(self.push_index);

            self.push_index += 1;

            if (self.push_index >= queue_size) {
                self.push_index = 0;
            }

            ptr.* = item;
        }

        pub fn Length(self: Self) usize {
            return self.item_used_map.count();
        }

        pub fn HasItems(self: *Self) bool {
            return (self.pop_index == self.push_index);
        }

        pub fn Pop(self: *Self) StaticQueueError!T {
            const ptr = &self.items[self.pop_index];
            if (!self.item_used_map.isSet(self.pop_index)) {
                return StaticQueueError.QueueEmpty;
            }
            self.item_used_map.unset(self.pop_index);

            self.pop_index += 1;

            if (self.pop_index >= queue_size) {
                self.pop_index = 0;
            }

            return ptr.*;
        }
    };
}

test "push items" {
    var queue = StaticQueue(u32, 32){};

    for (0..5) |i| {
        try queue.Push(@intCast(10 * (i + 1)));
    }

    try testing.expect(queue.Length() == 5);

    try testing.expect(try queue.Pop() == 10);
    try testing.expect(try queue.Pop() == 20);

    try testing.expect(queue.Length() == 3);
}

test "append overflow" {
    var queue = StaticQueue(u32, 32){};
    for (0..32) |i| {
        try queue.Push(@intCast(i));
    }
    try testing.expectError(StaticQueueError.QueueFull, queue.Push(20));
}

test "pop and append after set full" {
    var queue = StaticQueue(u32, 32){};
    for (0..32) |i| {
        try queue.Push(@intCast(i));
    }

    _ = try queue.Pop();

    var has_error = false;

    _ = queue.Push(20) catch {
        has_error = true;
    };

    try testing.expect(has_error == false);
}

test "remove from empty set" {
    var queue = StaticQueue(u32, 32){};

    try testing.expectError(StaticQueueError.QueueEmpty, queue.Pop());
}

test "remove until empty" {
    var queue = StaticQueue(u32, 32){};

    for (0..5) |i| {
        try queue.Push(@intCast(i));
    }

    for (0..5) |_| {
        _ = try queue.Pop();
    }

    try testing.expectError(StaticQueueError.QueueEmpty, queue.Pop());
}

test "test structs" {
    const TestObj = struct {
        x: u32,
        y: f32,
    };

    var queue = StaticQueue(TestObj, 10){};

    for (0..5) |i| {
        const elem = TestObj{
            .x = @truncate(i),
            .y = @as(f32, @floatFromInt(i)) + 1.5,
        };
        try queue.Push(elem);
    }

    _ = try queue.Pop();
    const elem = try queue.Pop();

    try testing.expect(elem.x == 1 and elem.y == 2.5);
}
