//! Reaper daemon server bootstrap.

const std = @import("std");
const zrpc = @import("zrpc");
const zsync = @import("zsync");

const logging = @import("logging.zig");
const config_mod = @import("config/config.zig");
const services = @import("rpc/service.zig");
const handlers = @import("rpc/handlers.zig");

pub const LaunchOptions = struct {
    runtime: *zsync.Runtime,
    config: *const config_mod.Config,
    foreground: bool = false,
};

pub const ShutdownOptions = struct {
    config: *const config_mod.Config,
    force: bool = false,
};

const State = struct {
    allocator: std.mem.Allocator,
    server: *zrpc.Server,
    start_time_ms: i64,
};

var state: ?State = null;

pub fn launch(options: LaunchOptions) !void {
    if (state) |_| {
        logging.logger().warn("server already running", .{});
        return;
    }

    const allocator = options.runtime.allocator;

    const server_ptr = try allocator.create(zrpc.Server);
    errdefer allocator.destroy(server_ptr);

    server_ptr.* = zrpc.Server.init(allocator);
    errdefer server_ptr.deinit();

    try services.registerAll(server_ptr);

    const start_time = std.time.milliTimestamp();
    handlers.setContext(.{ .start_time_ms = start_time });
    try handlers.registerAll(server_ptr);

    state = .{
        .allocator = allocator,
        .server = server_ptr,
        .start_time_ms = start_time,
    };

    logging.logger().info(
        "Reaper daemon listening on {s}:{d} (foreground={})",
        .{ options.config.daemon.host, options.config.daemon.port, options.foreground },
    );

    if (options.foreground) {
        try runForeground(server_ptr, options.config);
    }
}

pub fn shutdown(options: ShutdownOptions) !void {
    if (state) |s| {
        s.server.stop();
        s.server.deinit();
        s.allocator.destroy(s.server);
        state = null;
    logging.logger().info("Reaper daemon stopped (force={})", .{options.force});
    } else {
        logging.logger().warn("reaper daemon was not running", .{});
    }
}

fn runForeground(server_ptr: *zrpc.Server, config: *const config_mod.Config) !void {
    const endpoint = try std.fmt.allocPrint(std.heap.page_allocator, "{s}:{d}", .{ config.daemon.host, config.daemon.port });
    defer std.heap.page_allocator.free(endpoint);

    logging.logger().info("Starting foreground loop on {s}", .{endpoint});
    server_ptr.serve(endpoint) catch |err| {
    logging.logger().err("Server exited with error: {s}", .{@errorName(err)});
        return err;
    };
}
