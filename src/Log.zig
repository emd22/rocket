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
    // Renderer Methods
    RenDebug,
    RenInfo,
    RenWarn,
    RenError,
    RenFatal,
};

pub var ThreadSafe = true;
pub var OutputWriter = std.io.getStdOut().writer();

var LogMutex = std.Thread.Mutex{};

const Tuple = std.meta.Tuple;

const Builtin = @import("builtin");

pub fn GetMutex() *std.Thread.Mutex {
    return &LogMutex;
}

pub inline fn YesNo(value: bool) []const u8 {
    return if (value) "Yes" else "No";
}

fn InternLog(comptime level: Level, comptime fmt: []const u8, args: anytype) void {
    // omit when we are building in Release mode
    if (comptime (level != .Error and level != .Fatal) and Builtin.mode != .Debug) {
        return;
    }

    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
    }

    const data: Tuple(&.{ TextColor, []const u8, bool }) = switch (level) {
        .Debug => .{ TextColor.Debug, "Debug", false },
        .Info => .{ TextColor.Info, "Info", false },
        .Warn => .{ TextColor.Warn, "Warn", false },
        .Error => .{ TextColor.Error, "Error", false },
        .Fatal => .{ TextColor.Error, "Fatal", false },
        // Renderer specific
        .RenDebug => .{ TextColor.Debug, "RenDebug", true },
        .RenInfo => .{ TextColor.Info, "RenInfo", true },
        .RenWarn => .{ TextColor.Warn, "RenWarn", true },
        .RenError => .{ TextColor.Error, "RenError", true },
        .RenFatal => .{ TextColor.Error, "RenFatal", true },
    };

    try OutputWriter.print("\x1b[{s}{d}m[{s}]\x1b[0m ", .{
        if (data[2]) "1;" else "",
        @intFromEnum(data[0]),
        data[1],
    });

    try OutputWriter.print(fmt, args);
    try OutputWriter.writeByte('\n');

    if (ThreadSafe) {
        LogMutex.unlock();
    }
}

pub fn SetColor(color: TextColor) void {
    errdefer @panic("Could not set text color(could not log to output stream)");

    if (ThreadSafe) {
        LogMutex.lock();
    }

    try OutputWriter.print("\x1b[{d}m", .{@intFromEnum(color)});

    if (ThreadSafe) {
        defer LogMutex.unlock();
    }
}

pub fn Custom(color: TextColor, pretext: []const u8, comptime fmt: []const u8, args: anytype) void {
    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
    }

    try OutputWriter.print("\x1b[{d}m{s}\x1b[0m ", .{ @intFromEnum(color), pretext });

    try OutputWriter.print(fmt, args);
    try OutputWriter.writeByte('\n');

    if (ThreadSafe) {
        defer LogMutex.unlock();
    }
}

pub fn WriteRaw(comptime fmt: []const u8, args: anytype) void {
    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
    }
    try OutputWriter.print(fmt, args);

    if (ThreadSafe) {
        defer LogMutex.unlock();
    }
}

pub fn WriteChar(value: u8) void {
    errdefer @panic("Could not log to stream");

    if (ThreadSafe) {
        LogMutex.lock();
    }

    try OutputWriter.writeByte(value);

    if (ThreadSafe) {
        defer LogMutex.unlock();
    }
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

///////////////////////////////
// Renderer Methods
///////////////////////////////

pub fn RenDebug(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.RenDebug, fmt, args);
}

pub fn RenWarn(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.RenWarn, fmt, args);
}

pub fn RenError(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.RenError, fmt, args);
}

pub fn RenInfo(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.RenInfo, fmt, args);
}

pub fn RenFatal(comptime fmt: []const u8, args: anytype) void {
    InternLog(Level.RenFatal, fmt, args);
}
