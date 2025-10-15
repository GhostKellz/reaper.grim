//! Model capability detection example

const std = @import("std");
const reaper = @import("reaper_grim");

const capabilities = reaper.providers.capabilities;
const provider = reaper.providers.provider;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize capability registry
    var cap_registry = capabilities.CapabilityRegistry.init(allocator);
    defer cap_registry.deinit();

    std.debug.print("=== Model Capability Detection ===\n\n", .{});

    // Check specific model capabilities
    std.debug.print("GPT-4 Turbo capabilities:\n", .{});
    if (cap_registry.getCapabilities(.openai, "gpt-4-turbo")) |caps| {
        printCapabilities(caps);
    }

    std.debug.print("\nClaude 3.5 Sonnet capabilities:\n", .{});
    if (cap_registry.getCapabilities(.anthropic, "claude-3-5-sonnet-20241022")) |caps| {
        printCapabilities(caps);
    }

    // Find models with specific requirements
    std.debug.print("\n=== Finding Models ===\n", .{});

    std.debug.print("\nModels with function calling:\n", .{});
    const with_functions = try cap_registry.findModels(allocator, null, true, false);
    defer allocator.free(with_functions);

    for (with_functions) |info| {
        std.debug.print("  - {s} ({s})\n", .{ info.display_name, info.model_id });
    }

    std.debug.print("\nModels with vision support:\n", .{});
    const with_vision = try cap_registry.findModels(allocator, null, false, true);
    defer allocator.free(with_vision);

    for (with_vision) |info| {
        std.debug.print("  - {s} ({s})\n", .{ info.display_name, info.model_id });
    }

    std.debug.print("\nModels with 100K+ context:\n", .{});
    const large_context = try cap_registry.findModels(allocator, 100000, false, false);
    defer allocator.free(large_context);

    for (large_context) |info| {
        std.debug.print("  - {s}: {d}K tokens\n", .{
            info.display_name,
            info.capabilities.max_context_tokens / 1000,
        });
    }

    // Cost comparison
    std.debug.print("\n=== Cost Comparison (per 1M tokens) ===\n", .{});
    const all_models = try cap_registry.findModels(allocator, null, false, false);
    defer allocator.free(all_models);

    for (all_models) |info| {
        if (info.capabilities.input_cost_per_1m) |in_cost| {
            const out_cost = info.capabilities.output_cost_per_1m orelse 0.0;
            std.debug.print("{s:30} ${d:.2} in / ${d:.2} out\n", .{
                info.display_name,
                in_cost,
                out_cost,
            });
        }
    }
}

fn printCapabilities(caps: capabilities.ModelCapabilities) void {
    std.debug.print("  Context: {d} tokens\n", .{caps.max_context_tokens});
    std.debug.print("  Output: {d} tokens\n", .{caps.max_output_tokens});
    std.debug.print("  Functions: {s}\n", .{if (caps.supports_functions) "Yes" else "No"});
    std.debug.print("  Vision: {s}\n", .{if (caps.supports_vision) "Yes" else "No"});
    std.debug.print("  JSON mode: {s}\n", .{if (caps.supports_json_mode) "Yes" else "No"});
    std.debug.print("  Streaming: {s}\n", .{if (caps.supports_streaming) "Yes" else "No"});

    if (caps.input_cost_per_1m) |cost| {
        std.debug.print("  Input cost: ${d:.2}/1M tokens\n", .{cost});
    }
    if (caps.output_cost_per_1m) |cost| {
        std.debug.print("  Output cost: ${d:.2}/1M tokens\n", .{cost});
    }
    if (caps.knowledge_cutoff) |cutoff| {
        std.debug.print("  Knowledge cutoff: {s}\n", .{cutoff});
    }
}

/// Example: Selecting the best model for a task
fn selectBestModel(
    allocator: std.mem.Allocator,
    cap_registry: *capabilities.CapabilityRegistry,
    requirements: TaskRequirements,
) !?capabilities.ModelInfo {
    const models = try cap_registry.findModels(
        allocator,
        requirements.min_context,
        requirements.needs_functions,
        requirements.needs_vision,
    );
    defer allocator.free(models);

    if (models.len == 0) return null;

    // Find cheapest model that meets requirements
    var best: ?capabilities.ModelInfo = null;
    var best_cost: f64 = std.math.floatMax(f64);

    for (models) |model| {
        if (model.capabilities.input_cost_per_1m) |cost| {
            if (cost < best_cost) {
                best_cost = cost;
                best = model;
            }
        }
    }

    return best;
}

const TaskRequirements = struct {
    min_context: ?u32,
    needs_functions: bool,
    needs_vision: bool,
};

/// Example: Estimating request cost
fn estimateRequestCost(
    caps: capabilities.ModelCapabilities,
    input_tokens: u32,
    output_tokens: u32,
) ?f64 {
    const in_cost = caps.input_cost_per_1m orelse return null;
    const out_cost = caps.output_cost_per_1m orelse return null;

    const in_price = in_cost * @as(f64, @floatFromInt(input_tokens)) / 1_000_000.0;
    const out_price = out_cost * @as(f64, @floatFromInt(output_tokens)) / 1_000_000.0;

    return in_price + out_price;
}
