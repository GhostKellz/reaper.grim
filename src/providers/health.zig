//! Provider health checking and monitoring.

const std = @import("std");
const provider = @import("provider.zig");

/// Health status of a provider
pub const HealthStatus = enum {
    healthy,
    degraded,
    unhealthy,
    unknown,
};

/// Health check result
pub const HealthCheck = struct {
    status: HealthStatus,
    last_check: i64,
    consecutive_failures: u32,
    response_time_ms: ?u32,
    error_message: ?[]const u8,

    pub fn deinit(self: *HealthCheck, allocator: std.mem.Allocator) void {
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Health check configuration
pub const HealthCheckConfig = struct {
    /// Interval between health checks in seconds
    check_interval_s: u32 = 60,
    /// Number of consecutive failures before marking unhealthy
    failure_threshold: u32 = 3,
    /// Number of consecutive successes to recover from degraded
    recovery_threshold: u32 = 2,
    /// Timeout for health check requests in milliseconds
    timeout_ms: u32 = 5000,
    /// Response time threshold for degraded status in milliseconds
    degraded_threshold_ms: u32 = 2000,
};

/// Provider health monitor
pub const HealthMonitor = struct {
    allocator: std.mem.Allocator,
    config: HealthCheckConfig,
    statuses: std.AutoHashMap(provider.Kind, HealthCheck),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, config: HealthCheckConfig) HealthMonitor {
        return .{
            .allocator = allocator,
            .config = config,
            .statuses = std.AutoHashMap(provider.Kind, HealthCheck).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *HealthMonitor) void {
        var it = self.statuses.iterator();
        while (it.next()) |entry| {
            var check = entry.value_ptr.*;
            check.deinit(self.allocator);
        }
        self.statuses.deinit();
    }

    /// Get health status for a provider
    pub fn getStatus(self: *HealthMonitor, kind: provider.Kind) HealthStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.statuses.get(kind)) |check| {
            return check.status;
        }

        return .unknown;
    }

    /// Record successful request
    pub fn recordSuccess(self: *HealthMonitor, kind: provider.Kind, response_time_ms: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var check = self.statuses.get(kind) orelse HealthCheck{
            .status = .unknown,
            .last_check = std.time.timestamp(),
            .consecutive_failures = 0,
            .response_time_ms = null,
            .error_message = null,
        };

        check.last_check = std.time.timestamp();
        check.consecutive_failures = 0;
        check.response_time_ms = response_time_ms;

        // Determine status based on response time
        if (response_time_ms > self.config.degraded_threshold_ms) {
            check.status = .degraded;
        } else {
            check.status = .healthy;
        }

        try self.statuses.put(kind, check);
    }

    /// Record failed request
    pub fn recordFailure(self: *HealthMonitor, kind: provider.Kind, error_message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var check = self.statuses.get(kind) orelse HealthCheck{
            .status = .unknown,
            .last_check = std.time.timestamp(),
            .consecutive_failures = 0,
            .response_time_ms = null,
            .error_message = null,
        };

        // Clean up old error message
        if (check.error_message) |old_msg| {
            self.allocator.free(old_msg);
        }

        check.last_check = std.time.timestamp();
        check.consecutive_failures += 1;
        check.error_message = try self.allocator.dupe(u8, error_message);

        // Update status based on failure count
        if (check.consecutive_failures >= self.config.failure_threshold) {
            check.status = .unhealthy;
        } else {
            check.status = .degraded;
        }

        try self.statuses.put(kind, check);
    }

    /// Check if provider is available for requests
    pub fn isAvailable(self: *HealthMonitor, kind: provider.Kind) bool {
        const status = self.getStatus(kind);
        return status == .healthy or status == .degraded or status == .unknown;
    }

    /// Get all healthy providers
    pub fn getHealthyProviders(self: *HealthMonitor, allocator: std.mem.Allocator) ![]provider.Kind {
        self.mutex.lock();
        defer self.mutex.unlock();

        var healthy = std.ArrayList(provider.Kind){};
        defer healthy.deinit(allocator);

        var it = self.statuses.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.status == .healthy) {
                try healthy.append(allocator, entry.key_ptr.*);
            }
        }

        return healthy.toOwnedSlice(allocator);
    }
};

test "health monitor basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = HealthMonitor.init(allocator, .{});
    defer monitor.deinit();

    // Initially unknown
    try std.testing.expectEqual(HealthStatus.unknown, monitor.getStatus(.openai));

    // Record success
    try monitor.recordSuccess(.openai, 100);
    try std.testing.expectEqual(HealthStatus.healthy, monitor.getStatus(.openai));

    // Record failure
    try monitor.recordFailure(.openai, "test error");
    try std.testing.expectEqual(HealthStatus.degraded, monitor.getStatus(.openai));
}
