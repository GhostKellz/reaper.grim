//! Basic chat example demonstrating simple provider usage

const std = @import("std");
const reaper = @import("reaper_grim");

const vault = reaper.vault;
const registry = reaper.providers.registry;
const http = reaper.providers.http_types;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize vault
    var vault_instance = try vault.Vault.init(allocator, .{
        .backend = .gvault,
        .namespace = "reaper",
    });
    defer vault_instance.deinit();

    // Unlock vault (use environment variable or prompt)
    const passphrase = std.posix.getenv("REAPER_VAULT_PASS") orelse "default-password";
    try vault_instance.unlock(passphrase);

    // Create provider registry
    var provider_registry = registry.ProviderRegistry.init(allocator, &vault_instance);
    defer provider_registry.deinit();

    // Register OpenAI provider
    try provider_registry.registerOpenAI("default");

    // Create messages
    const messages = [_]http.Message{
        .{
            .role = "system",
            .content = "You are a helpful assistant.",
        },
        .{
            .role = "user",
            .content = "What is the capital of France?",
        },
    };

    // Make chat request
    var response = try provider_registry.chat(
        .openai,
        &messages,
        "gpt-3.5-turbo",
        500, // max_tokens
        0.7, // temperature
    );
    defer response.deinit(allocator);

    // Print response
    std.debug.print("Response: {s}\n", .{response.content});

    if (response.usage) |usage| {
        std.debug.print("Tokens: {d} in, {d} out, {d} total\n", .{
            usage.prompt_tokens,
            usage.completion_tokens,
            usage.total_tokens,
        });
    }
}
