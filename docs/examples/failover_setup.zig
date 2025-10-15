//! Advanced example: Provider failover with health monitoring

const std = @import("std");
const reaper = @import("reaper_grim");

const vault = reaper.vault;
const registry = reaper.providers.registry;
const health = reaper.providers.health;
const failover = reaper.providers.failover;
const provider = reaper.providers.provider;
const http = reaper.providers.http_types;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize vault
    var vault_instance = try vault.Vault.init(allocator, .{
        .backend = .gvault,
    });
    defer vault_instance.deinit();

    const passphrase = std.posix.getenv("REAPER_VAULT_PASS") orelse "default-password";
    try vault_instance.unlock(passphrase);

    // Create provider registry
    var provider_registry = registry.ProviderRegistry.init(allocator, &vault_instance);
    defer provider_registry.deinit();

    // Register multiple providers
    try provider_registry.registerOpenAI("default");
    try provider_registry.registerAnthropic("default");
    try provider_registry.registerOllama(null); // Local fallback

    // Initialize health monitor
    var health_monitor = health.HealthMonitor.init(allocator, .{
        .check_interval_s = 60,
        .failure_threshold = 3,
        .recovery_threshold = 2,
    });
    defer health_monitor.deinit();

    // Initialize failover manager
    var failover_manager = failover.FailoverManager.init(
        allocator,
        .{ .strategy = .priority },
        &health_monitor,
    );
    defer failover_manager.deinit();

    // Set provider priorities
    const priorities = [_]failover.ProviderPriority{
        .{ .kind = .anthropic, .priority = 1 }, // Try first (best value)
        .{ .kind = .openai, .priority = 2 }, // Try second
        .{ .kind = .ollama, .priority = 3 }, // Local fallback (free)
    };

    try failover_manager.setPriorities(&priorities);

    // Define chat request context
    const ChatContext = struct {
        registry: *registry.ProviderRegistry,
        messages: []const http.Message,
        model_by_provider: std.AutoHashMap(provider.Kind, []const u8),
    };

    var model_map = std.AutoHashMap(provider.Kind, []const u8).init(allocator);
    defer model_map.deinit();

    try model_map.put(.anthropic, "claude-3-5-sonnet-20241022");
    try model_map.put(.openai, "gpt-4o");
    try model_map.put(.ollama, "llama3:latest");

    const messages = [_]http.Message{
        .{ .role = "user", .content = "Explain quantum entanglement" },
    };

    var context = ChatContext{
        .registry = &provider_registry,
        .messages = &messages,
        .model_by_provider = model_map,
    };

    // Function to execute with automatic failover
    const makeRequest = struct {
        fn execute(ctx: *ChatContext, kind: provider.Kind) !http.CompletionResponse {
            const model = ctx.model_by_provider.get(kind) orelse return error.InvalidRequest;
            return try ctx.registry.chat(kind, ctx.messages, model, 1000, 0.7);
        }
    }.execute;

    // Execute with automatic failover
    var response = try failover_manager.executeWithFailover(
        http.CompletionResponse,
        http.ProviderError,
        &context,
        makeRequest,
    );
    defer response.deinit(allocator);

    std.debug.print("Response: {s}\n", .{response.content});
    std.debug.print("Model: {s}\n", .{response.model});

    // Check health status
    std.debug.print("\nProvider Health Status:\n", .{});
    const descriptors = provider.descriptors();
    for (descriptors) |desc| {
        const status = health_monitor.getStatus(desc.kind);
        const status_str = switch (status) {
            .healthy => "✓ Healthy",
            .degraded => "⚠ Degraded",
            .unhealthy => "✗ Unhealthy",
            .unknown => "? Unknown",
        };
        std.debug.print("  {s}: {s}\n", .{ desc.display_name, status_str });
    }
}
