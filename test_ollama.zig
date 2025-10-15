const std = @import("std");
const ollama = @import("src/providers/ollama.zig");
const http_types = @import("src/providers/http_types.zig");
const vault = @import("src/auth/vault.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create Ollama provider
    var provider = ollama.OllamaProvider.init(allocator, null);
    defer provider.deinit();

    std.debug.print("Testing Ollama provider...\n", .{});

    // List available models
    std.debug.print("\nFetching available models...\n", .{});
    const models = try provider.listModels();
    defer {
        for (models) |model| {
            allocator.free(model);
        }
        allocator.free(models);
    }

    std.debug.print("Found {d} models:\n", .{models.len});
    for (models) |model| {
        std.debug.print("  - {s}\n", .{model});
    }

    // Test chat completion with a simple message
    std.debug.print("\nTesting chat completion with llama3:latest...\n", .{});
    const messages = [_]http_types.Message{
        .{ .role = "user", .content = "Say hello in one short sentence." },
    };

    const response = try provider.chat(&messages, "llama3:latest", 100, 0.7);
    defer {
        allocator.free(response.id);
        allocator.free(response.model);
        allocator.free(response.content);
        if (response.finish_reason) |reason| allocator.free(reason);
    }

    std.debug.print("\nResponse:\n", .{});
    std.debug.print("  ID: {s}\n", .{response.id});
    std.debug.print("  Model: {s}\n", .{response.model});
    std.debug.print("  Content: {s}\n", .{response.content});
    if (response.finish_reason) |reason| {
        std.debug.print("  Finish Reason: {s}\n", .{reason});
    }
    if (response.usage) |usage| {
        std.debug.print("  Usage: {d} prompt + {d} completion = {d} total tokens\n", .{
            usage.prompt_tokens,
            usage.completion_tokens,
            usage.total_tokens,
        });
    }

    std.debug.print("\n✓ Ollama provider test successful!\n", .{});
}
