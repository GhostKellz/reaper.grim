//! RPC handlers for Reaper services.

const std = @import("std");
const zrpc = @import("zrpc");

const services = @import("service.zig");
const version = @import("../version.zig");
const logging = @import("../logging.zig");

pub const ServerContext = struct {
    start_time_ms: i64,
};

var server_context: ?ServerContext = null;

pub fn setContext(ctx: ServerContext) void {
    server_context = ctx;
}

pub fn registerAll(server: *zrpc.Server) !void {
    try server.registerHandler(
        services.HealthService.name,
        services.HealthService.Method.check.name,
        zrpc.service.MethodHandler.unary(healthCheck),
    );
}

fn healthCheck(ctx: *zrpc.service.CallContext, request_body: []const u8) zrpc.Error![]u8 {
    const request = zrpc.codec.JsonCodec.decode(ctx.allocator, request_body, services.HealthService.Request) catch services.HealthService.Request{};
    if (request.request_id) |id| {
        logging.logger().info(
            "Health request received (id={s}, include_metrics={})",
            .{ id, request.include_metrics },
        );
    }

    const info = server_context orelse return zrpc.Error.Internal;
    const now_ms = std.time.milliTimestamp();
    const uptime = if (now_ms > info.start_time_ms) blk: {
        const delta = now_ms - info.start_time_ms;
        break :blk @as(u64, @intCast(delta));
    } else 0;

    const response = services.HealthService.Response{
        .uptime_ms = uptime,
        .version = version.VERSION,
    };

    return zrpc.codec.JsonCodec.encode(ctx.allocator, response);
}
