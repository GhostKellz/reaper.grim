//! Service definitions for the Reaper RPC surface.

const zrpc = @import("zrpc");

pub const HealthService = struct {
    pub const name = "reaper.Health";

    pub const Method = struct {
        pub const check = zrpc.service.MethodDef{
            .name = "Check",
            .call_type = .unary,
        };
    };

    pub const definition = zrpc.service.ServiceDef{
        .name = name,
        .methods = &.{ Method.check },
    };

    pub const Request = struct {
        request_id: ?[]const u8 = null,
        include_metrics: bool = false,
    };

    pub const Response = struct {
        status: []const u8 = "SERVING",
        uptime_ms: u64 = 0,
        version: []const u8,
    };
};

pub fn registerAll(server: *zrpc.Server) !void {
    try server.registerService(HealthService.definition);
}
