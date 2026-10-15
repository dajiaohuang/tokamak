const std = @import("std");
const log = std.log.scoped(.config);

const DEFAULT_PATH = "config.json";

const ReadOptions = struct {
    path: []const u8 = DEFAULT_PATH,
    cwd: ?std.Io.Dir = null,
    // TODO: alloc_always should not be overridable (or we should accept arena)
    parse: std.json.ParseOptions = .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
};

pub fn read(comptime T: type, io: std.Io, gpa: std.mem.Allocator, options: ReadOptions) !std.json.Parsed(T) {
    const cwd = options.cwd orelse std.Io.Dir.cwd();

    const contents = cwd.readFileAlloc(io, options.path, gpa, .unlimited) catch |e| switch (e) {
        error.FileNotFound => return std.json.parseFromSlice(T, gpa, "{}", .{}),
        else => return e,
    };
    defer gpa.free(contents);

    return try std.json.parseFromSlice(T, gpa, contents, options.parse);
}

const WriteOptions = struct {
    path: []const u8 = DEFAULT_PATH,
    cwd: ?std.Io.Dir = null,
    stringify: std.json.Stringify.Options = .{ .whitespace = .indent_2 },
};

pub fn write(comptime T: type, io: std.Io, config: T, options: WriteOptions) !void {
    const cwd = options.cwd orelse std.Io.Dir.cwd();

    const file = try cwd.createFile(io, options.path, .{});
    defer file.close(io);

    var writer = file.writer(io, &.{});
    try std.json.Stringify.value(config, options.stringify, &writer.interface);
    try writer.interface.flush();
}

test "write and read configuration" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const Config = struct { name: []const u8, count: u32 };
    try write(Config, std.testing.io, .{ .name = "tokamak", .count = 7 }, .{ .cwd = tmp.dir });
    const parsed = try read(Config, std.testing.io, std.testing.allocator, .{ .cwd = tmp.dir });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("tokamak", parsed.value.name);
    try std.testing.expectEqual(@as(u32, 7), parsed.value.count);
}
