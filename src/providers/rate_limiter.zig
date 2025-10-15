//! Rate limiting and retry logic for API providers.
//! Uses token bucket algorithm for rate limiting and exponential backoff for retries.

const std = @import("std");

/// Rate limiter configuration
pub const RateLimiterConfig = struct {
    /// Maximum tokens (requests) in bucket
    max_tokens: u32 = 60,
    /// Tokens refilled per second
    refill_rate: u32 = 1,
    /// Maximum number of retry attempts
    max_retries: u32 = 3,
    /// Base delay in milliseconds for exponential backoff
    base_delay_ms: u32 = 1000,
    /// Maximum delay in milliseconds
    max_delay_ms: u32 = 60000,
};

/// Token bucket rate limiter
pub const RateLimiter = struct {
    config: RateLimiterConfig,
    tokens: f64,
    last_refill: i64,
    mutex: std.Thread.Mutex,

    pub fn init(config: RateLimiterConfig) RateLimiter {
        return .{
            .config = config,
            .tokens = @floatFromInt(config.max_tokens),
            .last_refill = std.time.timestamp(),
            .mutex = .{},
        };
    }

    /// Acquire a token, blocking if necessary
    pub fn acquire(self: *RateLimiter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (true) {
            self.refill();

            if (self.tokens >= 1.0) {
                self.tokens -= 1.0;
                return;
            }

            // Calculate wait time until next token
            const time_until_token = @as(u64, @intFromFloat(1000.0 / @as(f64, @floatFromInt(self.config.refill_rate)) * std.time.ns_per_ms));

            // Release mutex while sleeping
            self.mutex.unlock();
            std.Thread.sleep(time_until_token);
            self.mutex.lock();
        }
    }

    /// Try to acquire a token without blocking
    pub fn tryAcquire(self: *RateLimiter) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.refill();

        if (self.tokens >= 1.0) {
            self.tokens -= 1.0;
            return true;
        }

        return false;
    }

    /// Refill tokens based on elapsed time
    fn refill(self: *RateLimiter) void {
        const now = std.time.timestamp();
        const elapsed = now - self.last_refill;

        if (elapsed > 0) {
            const tokens_to_add = @as(f64, @floatFromInt(elapsed)) * @as(f64, @floatFromInt(self.config.refill_rate));
            self.tokens = @min(self.tokens + tokens_to_add, @as(f64, @floatFromInt(self.config.max_tokens)));
            self.last_refill = now;
        }
    }
};

/// Retry context for exponential backoff
pub const RetryContext = struct {
    config: RateLimiterConfig,
    attempt: u32 = 0,

    pub fn init(config: RateLimiterConfig) RetryContext {
        return .{ .config = config };
    }

    /// Check if more retries are allowed
    pub fn shouldRetry(self: *RetryContext) bool {
        return self.attempt < self.config.max_retries;
    }

    /// Sleep with exponential backoff and increment attempt counter
    pub fn backoff(self: *RetryContext) void {
        if (!self.shouldRetry()) return;

        // Calculate exponential backoff: base_delay * 2^attempt
        const delay_ms = @min(
            self.config.base_delay_ms * (@as(u32, 1) << @intCast(self.attempt)),
            self.config.max_delay_ms,
        );

        // Add jitter (±25%)
        const jitter_range = delay_ms / 4;
        const jitter = @as(i32, @intCast(std.crypto.random.intRangeAtMost(u32, 0, jitter_range * 2))) - @as(i32, @intCast(jitter_range));
        const final_delay = @as(u64, @intCast(@as(i64, @intCast(delay_ms)) + jitter));

        std.Thread.sleep(final_delay * std.time.ns_per_ms);
        self.attempt += 1;
    }

    /// Reset retry counter
    pub fn reset(self: *RetryContext) void {
        self.attempt = 0;
    }
};

/// Execute a function with retry logic
pub fn withRetry(
    comptime T: type,
    comptime ErrorSet: type,
    config: RateLimiterConfig,
    context: anytype,
    comptime func: fn (@TypeOf(context)) ErrorSet!T,
) ErrorSet!T {
    var retry_ctx = RetryContext.init(config);

    while (true) {
        const result = func(context) catch |err| {
            // Only retry on specific errors
            const should_retry = switch (err) {
                error.RateLimited, error.ServerError, error.NetworkError => true,
                else => false,
            };

            if (should_retry and retry_ctx.shouldRetry()) {
                retry_ctx.backoff();
                continue;
            }

            return err;
        };

        return result;
    }
}

test "rate limiter basic" {
    var limiter = RateLimiter.init(.{
        .max_tokens = 5,
        .refill_rate = 10, // 10 tokens per second
    });

    // Should acquire immediately
    try std.testing.expect(limiter.tryAcquire());
    try std.testing.expect(limiter.tryAcquire());
}

test "retry context exponential backoff" {
    var ctx = RetryContext.init(.{
        .max_retries = 3,
        .base_delay_ms = 100,
        .max_delay_ms = 1000,
    });

    try std.testing.expect(ctx.shouldRetry());
    try std.testing.expectEqual(@as(u32, 0), ctx.attempt);

    ctx.backoff();
    try std.testing.expectEqual(@as(u32, 1), ctx.attempt);

    ctx.reset();
    try std.testing.expectEqual(@as(u32, 0), ctx.attempt);
}
