//! Provider failover and load balancing.

const std = @import("std");
const provider = @import("provider.zig");
const health = @import("health.zig");

/// Failover strategy
pub const FailoverStrategy = enum {
    /// Try providers in priority order
    priority,
    /// Round-robin across healthy providers
    round_robin,
    /// Random selection from healthy providers
    random,
    /// Weighted random based on response times
    weighted,
};

/// Failover configuration
pub const FailoverConfig = struct {
    strategy: FailoverStrategy = .priority,
    /// Maximum providers to try before giving up
    max_attempts: u32 = 3,
    /// Prefer providers with this capability
    required_capability: ?provider.Capability = null,
};

/// Provider with priority
pub const ProviderPriority = struct {
    kind: provider.Kind,
    priority: u32, // Lower number = higher priority
};

/// Failover manager
pub const FailoverManager = struct {
    allocator: std.mem.Allocator,
    config: FailoverConfig,
    health_monitor: *health.HealthMonitor,
    priorities: std.ArrayList(ProviderPriority),
    round_robin_index: usize,
    mutex: std.Thread.Mutex,

    pub fn init(
        allocator: std.mem.Allocator,
        config: FailoverConfig,
        health_monitor: *health.HealthMonitor,
    ) FailoverManager {
        return .{
            .allocator = allocator,
            .config = config,
            .health_monitor = health_monitor,
            .priorities = std.ArrayList(ProviderPriority){},
            .round_robin_index = 0,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *FailoverManager) void {
        self.priorities.deinit(self.allocator);
    }

    /// Set provider priorities (lower number = higher priority)
    pub fn setPriorities(self: *FailoverManager, priorities: []const ProviderPriority) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.priorities.clearRetainingCapacity();
        for (priorities) |p| {
            try self.priorities.append(self.allocator, p);
        }

        // Sort by priority (ascending)
        std.mem.sort(ProviderPriority, self.priorities.items, {}, struct {
            fn lessThan(_: void, a: ProviderPriority, b: ProviderPriority) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }

    /// Get next provider to try based on failover strategy
    pub fn selectProvider(self: *FailoverManager) ?provider.Kind {
        self.mutex.lock();
        defer self.mutex.unlock();

        return switch (self.config.strategy) {
            .priority => self.selectByPriority(),
            .round_robin => self.selectRoundRobin(),
            .random => self.selectRandom(),
            .weighted => self.selectWeighted(),
        };
    }

    /// Select provider by priority order (first healthy)
    fn selectByPriority(self: *FailoverManager) ?provider.Kind {
        for (self.priorities.items) |p| {
            if (self.health_monitor.isAvailable(p.kind)) {
                return p.kind;
            }
        }
        return null;
    }

    /// Select provider using round-robin
    fn selectRoundRobin(self: *FailoverManager) ?provider.Kind {
        if (self.priorities.items.len == 0) return null;

        const start_index = self.round_robin_index;
        var attempts: usize = 0;

        while (attempts < self.priorities.items.len) : (attempts += 1) {
            const index = (start_index + attempts) % self.priorities.items.len;
            const p = self.priorities.items[index];

            if (self.health_monitor.isAvailable(p.kind)) {
                self.round_robin_index = (index + 1) % self.priorities.items.len;
                return p.kind;
            }
        }

        return null;
    }

    /// Select provider randomly from healthy ones
    fn selectRandom(self: *FailoverManager) ?provider.Kind {
        var healthy = std.ArrayList(provider.Kind){};
        defer healthy.deinit(self.allocator);

        for (self.priorities.items) |p| {
            if (self.health_monitor.isAvailable(p.kind)) {
                healthy.append(self.allocator, p.kind) catch continue;
            }
        }

        if (healthy.items.len == 0) return null;

        const index = std.crypto.random.intRangeLessThan(usize, 0, healthy.items.len);
        return healthy.items[index];
    }

    /// Select provider with weighted random based on response times
    fn selectWeighted(self: *FailoverManager) ?provider.Kind {
        // For now, fall back to priority
        // TODO: Implement weighted selection based on historical response times
        return self.selectByPriority();
    }

    /// Execute a request with automatic failover
    pub fn executeWithFailover(
        self: *FailoverManager,
        comptime T: type,
        comptime ErrorSet: type,
        context: anytype,
        comptime func: fn (@TypeOf(context), provider.Kind) ErrorSet!T,
    ) ErrorSet!T {
        var attempts: u32 = 0;
        var last_error: ?ErrorSet = null;

        while (attempts < self.config.max_attempts) : (attempts += 1) {
            const selected = self.selectProvider() orelse {
                if (last_error) |err| return err;
                return error.NoProviderAvailable;
            };

            const start_time = std.time.milliTimestamp();
            const result = func(context, selected) catch |err| {
                const elapsed = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

                // Record failure
                const error_name = @errorName(err);
                self.health_monitor.recordFailure(selected, error_name) catch {};

                last_error = err;
                continue;
            };

            // Record success
            const elapsed = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            self.health_monitor.recordSuccess(selected, elapsed) catch {};

            return result;
        }

        if (last_error) |err| return err;
        return error.NoProviderAvailable;
    }
};

test "failover priority selection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = health.HealthMonitor.init(allocator, .{});
    defer monitor.deinit();

    var manager = FailoverManager.init(allocator, .{ .strategy = .priority }, &monitor);
    defer manager.deinit();

    const priorities = [_]ProviderPriority{
        .{ .kind = .openai, .priority = 1 },
        .{ .kind = .anthropic, .priority = 2 },
    };

    try manager.setPriorities(&priorities);

    // Mark all as healthy
    try monitor.recordSuccess(.openai, 100);
    try monitor.recordSuccess(.anthropic, 100);

    // Should select highest priority (openai)
    const selected = manager.selectProvider();
    try std.testing.expect(selected != null);
    try std.testing.expectEqual(provider.Kind.openai, selected.?);
}
