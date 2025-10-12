const std = @import("std");
const zsync = @import("zsync");

const logging = @import("logging.zig");
const config_mod = @import("config/config.zig");
const cli = @import("cli/commands.zig");
const version = @import("version.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();

    var config_state = config_mod.loadOrDefault(allocator);
    defer config_state.deinit();
    const config = config_state.data();

    try logging.init(allocator, .{
        .level = config.logging.toLevel(),
        .file_path = config.logging.file_path,
    });
    defer logging.deinit();

    logging.logger().info("Reaper.grim starting (version {s})", .{version.VERSION});

    try cli.run(allocator, runtime, config);
}

test "simple test" {
    const allocator = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(allocator);
    try list.append(allocator, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
