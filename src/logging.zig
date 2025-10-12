//! Centralized logging subsystem powered by zlog.

const std = @import("std");
const zlog = @import("zlog");

pub const Options = struct {
    level: zlog.Level = .info,
    /// Optional log file path. When `null`, logs go to stderr.
    file_path: ?[]const u8 = null,
    /// Whether to mirror logs to stderr when a file target is configured.
    mirror_to_stderr: bool = true,
};

const State = struct {
    allocator: std.mem.Allocator,
    logger: *zlog.Logger,
    options: Options,
};

var state: ?State = null;

pub fn init(allocator: std.mem.Allocator, opts: Options) !void {
    if (state) |_| return; // already initialised

    const logger_ptr = try allocator.create(zlog.Logger);
    errdefer allocator.destroy(logger_ptr);

    const logger_config = zlog.LoggerConfig{
        .level = opts.level,
        .output_target = if (opts.file_path != null) .file else .stderr,
        .file_path = opts.file_path,
    };

    logger_ptr.* = try zlog.Logger.init(allocator, logger_config);

    // Mirror to stderr when writing to a file. zlog currently requires an
    // explicit tee; for now we emit a startup message to stderr instead.
    if (opts.file_path != null and opts.mirror_to_stderr) {
        std.log.info("logging to file: {s}", .{opts.file_path.?});
    }

    state = .{
        .allocator = allocator,
        .logger = logger_ptr,
        .options = opts,
    };
}

pub fn deinit() void {
    if (state) |s| {
        s.logger.deinit();
        s.allocator.destroy(s.logger);
        state = null;
    }
}

pub fn logger() *zlog.Logger {
    if (state) |s| {
        return s.logger;
    }
    @panic("logger not initialised");
}

pub fn level() zlog.Level {
    if (state) |s| return s.options.level;
    return .info;
}

pub fn currentOptions() Options {
    if (state) |s| return s.options;
    return .{};
}
