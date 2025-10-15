//! Provider registry for managing multiple API provider instances.

const std = @import("std");
const vault = @import("../auth/vault.zig");
const provider = @import("provider.zig");
const http = @import("http_types.zig");
const openai = @import("openai.zig");
const claude = @import("claude.zig");
const xai = @import("xai.zig");
const azure = @import("azure.zig");
const ollama = @import("ollama.zig");
const github_copilot = @import("github_copilot.zig");

pub const ProviderInstance = union(provider.Kind) {
    openai: openai.OpenAIProvider,
    anthropic: claude.ClaudeProvider,
    xai: xai.XAIProvider,
    azure_openai: azure.AzureOpenAIProvider,
    github_copilot: github_copilot.GitHubCopilotProvider,
    ollama: ollama.OllamaProvider,

    pub fn deinit(self: *ProviderInstance) void {
        switch (self.*) {
            .openai => |*p| p.deinit(),
            .anthropic => |*p| p.deinit(),
            .xai => |*p| p.deinit(),
            .azure_openai => |*p| p.deinit(),
            .github_copilot => |*p| p.deinit(),
            .ollama => |*p| p.deinit(),
        }
    }

    pub fn authenticate(self: *ProviderInstance, vault_instance: *vault.Vault) !void {
        switch (self.*) {
            .openai => |*p| try p.authenticate(vault_instance),
            .anthropic => |*p| try p.authenticate(vault_instance),
            .xai => |*p| try p.authenticate(vault_instance),
            .azure_openai => |*p| try p.authenticate(vault_instance),
            .github_copilot => |*p| try p.authenticate(vault_instance),
            .ollama => |*p| try p.authenticate(vault_instance),
        }
    }

    pub fn chat(
        self: *ProviderInstance,
        messages: []const http.Message,
        model: []const u8,
        max_tokens: ?u32,
        temperature: ?f32,
    ) !http.CompletionResponse {
        switch (self.*) {
            .openai => |*p| return p.chat(messages, model, max_tokens, temperature),
            .anthropic => |*p| return p.chat(messages, model, max_tokens, temperature),
            .xai => |*p| return p.chat(messages, model, max_tokens, temperature),
            .azure_openai => |*p| return p.chat(messages, model, max_tokens, temperature),
            .github_copilot => |*p| return p.chat(messages, model, max_tokens, temperature),
            .ollama => |*p| return p.chat(messages, model, max_tokens, temperature),
        }
    }
};

pub const ProviderRegistry = struct {
    allocator: std.mem.Allocator,
    vault_instance: *vault.Vault,
    providers: std.AutoHashMap(provider.Kind, ProviderInstance),

    pub fn init(allocator: std.mem.Allocator, vault_instance: *vault.Vault) ProviderRegistry {
        return .{
            .allocator = allocator,
            .vault_instance = vault_instance,
            .providers = std.AutoHashMap(provider.Kind, ProviderInstance).init(allocator),
        };
    }

    pub fn deinit(self: *ProviderRegistry) void {
        var it = self.providers.iterator();
        while (it.next()) |entry| {
            var inst = entry.value_ptr.*;
            inst.deinit();
        }
        self.providers.deinit();
    }

    pub fn registerOpenAI(self: *ProviderRegistry, account: []const u8) !void {
        var p = openai.OpenAIProvider.init(self.allocator, account);
        try p.authenticate(self.vault_instance);
        try self.providers.put(.openai, .{ .openai = p });
    }

    pub fn registerAnthropic(self: *ProviderRegistry, account: []const u8) !void {
        var p = claude.ClaudeProvider.init(self.allocator, account);
        try p.authenticate(self.vault_instance);
        try self.providers.put(.anthropic, .{ .anthropic = p });
    }

    pub fn registerXAI(self: *ProviderRegistry, account: []const u8) !void {
        var p = xai.XAIProvider.init(self.allocator, account);
        try p.authenticate(self.vault_instance);
        try self.providers.put(.xai, .{ .xai = p });
    }

    pub fn registerAzureOpenAI(
        self: *ProviderRegistry,
        account: []const u8,
        endpoint: []const u8,
        deployment: []const u8,
    ) !void {
        var p = azure.AzureOpenAIProvider.init(self.allocator, account, endpoint, deployment);
        try p.authenticate(self.vault_instance);
        try self.providers.put(.azure_openai, .{ .azure_openai = p });
    }

    pub fn registerOllama(self: *ProviderRegistry, base_url: ?[]const u8) !void {
        var p = ollama.OllamaProvider.init(self.allocator, base_url);
        try p.authenticate(self.vault_instance);
        try self.providers.put(.ollama, .{ .ollama = p });
    }

    pub fn registerGitHubCopilot(self: *ProviderRegistry, account: []const u8) !void {
        var p = github_copilot.GitHubCopilotProvider.init(self.allocator, account);
        try p.authenticate(self.vault_instance);
        try self.providers.put(.github_copilot, .{ .github_copilot = p });
    }

    pub fn get(self: *ProviderRegistry, kind: provider.Kind) ?*ProviderInstance {
        return self.providers.getPtr(kind);
    }

    pub fn has(self: *ProviderRegistry, kind: provider.Kind) bool {
        return self.providers.contains(kind);
    }

    pub fn chat(
        self: *ProviderRegistry,
        kind: provider.Kind,
        messages: []const http.Message,
        model: []const u8,
        max_tokens: ?u32,
        temperature: ?f32,
    ) !http.CompletionResponse {
        const p = self.get(kind) orelse return error.ProviderNotRegistered;
        return p.chat(messages, model, max_tokens, temperature);
    }
};
