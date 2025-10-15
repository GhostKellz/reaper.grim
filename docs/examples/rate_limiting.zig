//! Rate limiting and retry logic example

const std = @import("std");
const reaper = @import("reaper_grim");

const vault = reaper.vault;
const registry = reaper.providers.registry;
const rate_limiter = reaper.providers.rate_limiter;
const http = reaper.providers.http_types;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize vault
    var vault_instance = try vault.Vault.init(allocator, .{ .backend = .gvault });
    defer vault_instance.deinit();

    try vault_instance.unlock("default-password");

    // Create provider registry
    var provider_registry = registry.ProviderRegistry.init(allocator, &vault_instance);
    defer provider_registry.deinit();

    try provider_registry.registerOpenAI("default");

    // Configure rate limiter
    // OpenAI Tier 1: 500 RPM, 200K TPM
    const limiter_config = rate_limiter.RateLimiterConfig{
        .max_tokens = 500, // 500 requests in bucket
        .refill_rate = 500 / 60, // Refill 500/60 per second
        .max_retries = 3,
        .base_delay_ms = 1000, // Start with 1 second
        .max_delay_ms = 60000, // Max 60 seconds
    };

    var limiter = rate_limiter.RateLimiter.init(limiter_config);

    // Messages
    const messages = [_]http.Message{
        .{ .role = "user", .content = "Write a haiku about programming" },
    };

    // Execute with rate limiting
    std.debug.print("Making requests with rate limiting...\n", .{});

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        // Acquire rate limit token (blocks if necessary)
        limiter.acquire();

        std.debug.print("[Request {d}] Sending...", .{i + 1});

        // Make request with retry logic
        const RequestContext = struct {
            registry: *registry.ProviderRegistry,
            messages: []const http.Message,
        };

        var context = RequestContext{
            .registry = &provider_registry,
            .messages = &messages,
        };

        const executeRequest = struct {
            fn execute(ctx: *RequestContext) !http.CompletionResponse {
                return try ctx.registry.chat(
                    .openai,
                    ctx.messages,
                    "gpt-3.5-turbo",
                    100,
                    0.7,
                );
            }
        }.execute;

        // Execute with automatic retry
        var response = rate_limiter.withRetry(
            http.CompletionResponse,
            http.ProviderError,
            limiter_config,
            &context,
            executeRequest,
        ) catch |err| {
            std.debug.print(" Failed: {s}\n", .{@errorName(err)});
            continue;
        };
        defer response.deinit(allocator);

        std.debug.print(" Success!\n", .{});
        std.debug.print("  Response: {s}\n", .{response.content});

        // Small delay between requests
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    std.debug.print("\nRate limiting demonstration complete.\n", .{});
}

/// Example: Custom retry with exponential backoff
fn customRetryExample(allocator: std.mem.Allocator) !void {
    var retry_ctx = rate_limiter.RetryContext.init(.{
        .max_retries = 5,
        .base_delay_ms = 500,
        .max_delay_ms = 30000,
    });

    while (retry_ctx.shouldRetry()) {
        // Attempt operation
        const result = riskyOperation() catch |err| {
            std.debug.print("Attempt {d} failed: {s}\n", .{ retry_ctx.attempt + 1, @errorName(err) });

            // Backoff with exponential delay + jitter
            retry_ctx.backoff();
            continue;
        };

        std.debug.print("Success: {d}\n", .{result});
        return;
    }

    return error.MaxRetriesExceeded;
}

fn riskyOperation() !u32 {
    // Simulate 50% failure rate
    if (std.crypto.random.boolean()) {
        return error.TemporaryFailure;
    }
    return 42;
}

/// Example: Rate limiter with try-acquire (non-blocking)
fn nonBlockingExample() !void {
    var limiter = rate_limiter.RateLimiter.init(.{
        .max_tokens = 10,
        .refill_rate = 1,
    });

    // Try to acquire without blocking
    if (limiter.tryAcquire()) {
        std.debug.print("Token acquired, making request\n", .{});
        // Make request...
    } else {
        std.debug.print("Rate limit reached, queuing request\n", .{});
        // Queue for later or return error
    }
}
