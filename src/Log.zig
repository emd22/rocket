const std = @import("std");

pub const TextColor = enum(u32) {
    Reset = 0,
    Error = 91,
    Debug,
    Warn,
    Info,
};

pub const Level = enum(u8) {
    Debug,
    Info,
    Warn,
    Error,
    Fatal,
};

pub var ThreadSafe = true;
pub var OutputWriter = std.io.getStdOut().writer();

var LogMutex = std.Thread.Mutex{};

const Tuple = std.meta.Tuple;

const Builtin = @import("builtin");

pub fn GetMutex() *std.Thread.Mutex {
    return &LogMutex;
}

fn InternLog(comptime level: Level, comptime fmt: []const u8, args: anytype) void {
    if (comptime (level != .Error and level != .Fatal) and Builtin.mode != .Debug) {
        return;
    }

    // print when we cant print? lol
    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
        defer LogMutex.unlock();
    }

    const data: Tuple(&.{ TextColor, []const u8 }) = switch (level) {
        Level.Debug => .{ TextColor.Debug, "DEBUG" },
        Level.Info => .{ TextColor.Info, "INFO" },
        Level.Warn => .{ TextColor.Warn, "WARN" },
        Level.Error => .{ TextColor.Error, "ERROR" },
        Level.Fatal => .{ TextColor.Error, "FATAL" },
    };

    try OutputWriter.print("\x1b[{d}m[{s}]\x1b[0m ", .{ @intFromEnum(data[0]), data[1] });

    try OutputWriter.print(fmt, args);
    try OutputWriter.writeByte('\n');
}

pub fn Custom(color: TextColor, pretext: []const u8, comptime fmt: []const u8, args: anytype) void {
    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
        defer LogMutex.unlock();
    }

    try OutputWriter.print("\x1b[{d}m{s}\x1b[0m ", .{ @intFromEnum(color), pretext });

    try OutputWriter.print(fmt, args);
    try OutputWriter.writeByte('\n');
}

pub fn WriteRaw(comptime fmt: []const u8, args: anytype) void {
    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
        defer LogMutex.unlock();
    }
    try OutputWriter.print(fmt, args);
}

pub fn WriteChar(value: u8) void {
    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
        defer LogMutex.unlock();
    }
    try OutputWriter.writeByte(value);
}

pub fn Debug(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.Debug, fmt, args);
}

pub fn Warn(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.Warn, fmt, args);
}

pub fn Error(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.Error, fmt, args);
}

pub fn Info(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.Info, fmt, args);
}

pub fn Fatal(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.Fatal, fmt, args);
}
