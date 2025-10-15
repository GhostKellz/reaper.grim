//! Model capability detection and metadata.

const std = @import("std");
const provider = @import("provider.zig");

/// Detailed model capabilities
pub const ModelCapabilities = struct {
    /// Maximum context window size in tokens
    max_context_tokens: u32,
    /// Maximum output tokens
    max_output_tokens: u32,
    /// Supports function/tool calling
    supports_functions: bool = false,
    /// Supports vision/image inputs
    supports_vision: bool = false,
    /// Supports JSON mode
    supports_json_mode: bool = false,
    /// Supports streaming
    supports_streaming: bool = true,
    /// Input cost per 1M tokens (USD)
    input_cost_per_1m: ?f64 = null,
    /// Output cost per 1M tokens (USD)
    output_cost_per_1m: ?f64 = null,
    /// Model release/training cutoff date (YYYY-MM-DD)
    knowledge_cutoff: ?[]const u8 = null,
};

/// Model information
pub const ModelInfo = struct {
    provider_kind: provider.Kind,
    model_id: []const u8,
    display_name: []const u8,
    capabilities: ModelCapabilities,
};

/// Model capability registry
pub const CapabilityRegistry = struct {
    allocator: std.mem.Allocator,
    models: std.StringHashMap(ModelInfo),

    pub fn init(allocator: std.mem.Allocator) CapabilityRegistry {
        var registry = CapabilityRegistry{
            .allocator = allocator,
            .models = std.StringHashMap(ModelInfo).init(allocator),
        };

        // Pre-populate with known models
        registry.populateKnownModels() catch {};

        return registry;
    }

    pub fn deinit(self: *CapabilityRegistry) void {
        var it = self.models.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.models.deinit();
    }

    /// Register a model and its capabilities
    pub fn register(self: *CapabilityRegistry, info: ModelInfo) !void {
        const key = try std.fmt.allocPrint(
            self.allocator,
            "{s}:{s}",
            .{ provider.slug(info.provider_kind), info.model_id },
        );

        try self.models.put(key, info);
    }

    /// Get capabilities for a model
    pub fn getCapabilities(self: *CapabilityRegistry, provider_kind: provider.Kind, model_id: []const u8) ?ModelCapabilities {
        const key_buf = std.fmt.allocPrint(
            self.allocator,
            "{s}:{s}",
            .{ provider.slug(provider_kind), model_id },
        ) catch return null;
        defer self.allocator.free(key_buf);

        if (self.models.get(key_buf)) |info| {
            return info.capabilities;
        }

        return null;
    }

    /// Find models with specific capabilities
    pub fn findModels(
        self: *CapabilityRegistry,
        allocator: std.mem.Allocator,
        min_context: ?u32,
        requires_functions: bool,
        requires_vision: bool,
    ) ![]ModelInfo {
        var results = std.ArrayList(ModelInfo){};
        defer results.deinit(allocator);

        var it = self.models.valueIterator();
        while (it.next()) |info| {
            if (min_context) |min| {
                if (info.capabilities.max_context_tokens < min) continue;
            }

            if (requires_functions and !info.capabilities.supports_functions) continue;
            if (requires_vision and !info.capabilities.supports_vision) continue;

            try results.append(allocator, info.*);
        }

        return results.toOwnedSlice(allocator);
    }

    /// Populate registry with known model capabilities
    fn populateKnownModels(self: *CapabilityRegistry) !void {
        // OpenAI models
        try self.register(.{
            .provider_kind = .openai,
            .model_id = "gpt-4-turbo",
            .display_name = "GPT-4 Turbo",
            .capabilities = .{
                .max_context_tokens = 128000,
                .max_output_tokens = 4096,
                .supports_functions = true,
                .supports_vision = true,
                .supports_json_mode = true,
                .input_cost_per_1m = 10.0,
                .output_cost_per_1m = 30.0,
                .knowledge_cutoff = "2023-12",
            },
        });

        try self.register(.{
            .provider_kind = .openai,
            .model_id = "gpt-4o",
            .display_name = "GPT-4o",
            .capabilities = .{
                .max_context_tokens = 128000,
                .max_output_tokens = 4096,
                .supports_functions = true,
                .supports_vision = true,
                .supports_json_mode = true,
                .input_cost_per_1m = 5.0,
                .output_cost_per_1m = 15.0,
                .knowledge_cutoff = "2023-10",
            },
        });

        try self.register(.{
            .provider_kind = .openai,
            .model_id = "gpt-3.5-turbo",
            .display_name = "GPT-3.5 Turbo",
            .capabilities = .{
                .max_context_tokens = 16384,
                .max_output_tokens = 4096,
                .supports_functions = true,
                .supports_json_mode = true,
                .input_cost_per_1m = 0.5,
                .output_cost_per_1m = 1.5,
                .knowledge_cutoff = "2021-09",
            },
        });

        // Anthropic models
        try self.register(.{
            .provider_kind = .anthropic,
            .model_id = "claude-3-5-sonnet-20241022",
            .display_name = "Claude 3.5 Sonnet",
            .capabilities = .{
                .max_context_tokens = 200000,
                .max_output_tokens = 8192,
                .supports_functions = true,
                .supports_vision = true,
                .input_cost_per_1m = 3.0,
                .output_cost_per_1m = 15.0,
                .knowledge_cutoff = "2024-04",
            },
        });

        try self.register(.{
            .provider_kind = .anthropic,
            .model_id = "claude-3-opus-20240229",
            .display_name = "Claude 3 Opus",
            .capabilities = .{
                .max_context_tokens = 200000,
                .max_output_tokens = 4096,
                .supports_functions = true,
                .supports_vision = true,
                .input_cost_per_1m = 15.0,
                .output_cost_per_1m = 75.0,
                .knowledge_cutoff = "2023-08",
            },
        });

        // xAI models
        try self.register(.{
            .provider_kind = .xai,
            .model_id = "grok-2",
            .display_name = "Grok 2",
            .capabilities = .{
                .max_context_tokens = 128000,
                .max_output_tokens = 4096,
                .supports_functions = true,
                .input_cost_per_1m = 5.0,
                .output_cost_per_1m = 15.0,
            },
        });

        // Ollama models (dynamic - defaults)
        try self.register(.{
            .provider_kind = .ollama,
            .model_id = "llama3:latest",
            .display_name = "Llama 3",
            .capabilities = .{
                .max_context_tokens = 8192,
                .max_output_tokens = 2048,
                .input_cost_per_1m = 0.0, // Free local inference
                .output_cost_per_1m = 0.0,
            },
        });
    }
};

test "capability registry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var registry = CapabilityRegistry.init(allocator);
    defer registry.deinit();

    // Check GPT-4 capabilities
    const caps = registry.getCapabilities(.openai, "gpt-4-turbo");
    try std.testing.expect(caps != null);
    try std.testing.expect(caps.?.supports_vision);
    try std.testing.expect(caps.?.max_context_tokens == 128000);
}
