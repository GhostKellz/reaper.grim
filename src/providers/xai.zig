//! xAI (Grok) API provider implementation.
//! Note: xAI uses an OpenAI-compatible API.

const std = @import("std");
const http = @import("http_types.zig");
const vault = @import("../auth/vault.zig");
const zhttp = @import("zhttp");

pub const XAIProvider = struct {
    allocator: std.mem.Allocator,
    vault_ref: vault.SecretRef,
    api_key: ?[]u8 = null,
    base_url: []const u8 = "https://api.x.ai/v1",

    pub fn init(allocator: std.mem.Allocator, account: []const u8) XAIProvider {
        return .{
            .allocator = allocator,
            .vault_ref = vault.providerSecretRef(.xai, account, .api_key, null),
        };
    }

    pub fn deinit(self: *XAIProvider) void {
        if (self.api_key) |key| {
            self.allocator.free(key);
            self.api_key = null;
        }
    }

    pub fn authenticate(self: *XAIProvider, vault_instance: *vault.Vault) !void {
        if (self.api_key) |key| {
            self.allocator.free(key);
        }
        self.api_key = try vault_instance.fetch(self.vault_ref);
    }

    pub fn chat(
        self: *XAIProvider,
        messages: []const http.Message,
        model: []const u8,
        max_tokens: ?u32,
        temperature: ?f32,
    ) !http.CompletionResponse {
        const api_key = self.api_key orelse return http.ProviderError.AuthenticationFailed;

        // Build request JSON (OpenAI-compatible format)
        var request_json = std.ArrayList(u8){};
        defer request_json.deinit(self.allocator);

        try request_json.appendSlice(self.allocator, "{\"model\":\"");
        try request_json.appendSlice(self.allocator, model);
        try request_json.appendSlice(self.allocator, "\",\"messages\":[");

        for (messages, 0..) |msg, i| {
            if (i > 0) try request_json.appendSlice(self.allocator, ",");
            try request_json.appendSlice(self.allocator, "{\"role\":\"");
            try request_json.appendSlice(self.allocator, msg.role);
            try request_json.appendSlice(self.allocator, "\",\"content\":");

            // Properly encode content as JSON string
            var out: std.Io.Writer.Allocating = .init(self.allocator);
            defer out.deinit();
            try std.json.Stringify.value(msg.content, .{}, &out.writer);
            try request_json.appendSlice(self.allocator, out.written());

            try request_json.appendSlice(self.allocator, "}");
        }

        try request_json.appendSlice(self.allocator, "]");

        if (max_tokens) |tokens| {
            const tokens_str = try std.fmt.allocPrint(self.allocator, ",\"max_tokens\":{d}", .{tokens});
            defer self.allocator.free(tokens_str);
            try request_json.appendSlice(self.allocator, tokens_str);
        }

        if (temperature) |temp| {
            const temp_str = try std.fmt.allocPrint(self.allocator, ",\"temperature\":{d}", .{temp});
            defer self.allocator.free(temp_str);
            try request_json.appendSlice(self.allocator, temp_str);
        }

        try request_json.appendSlice(self.allocator, "}");

        // Build auth header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{api_key});
        defer self.allocator.free(auth_header);

        // Build URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url});
        defer self.allocator.free(url);

        // Make request
        const response_body = try http.makeJsonRequest(
            self.allocator,
            .POST,
            url,
            auth_header,
            request_json.items,
        );
        defer self.allocator.free(response_body);

        // Parse response (uses OpenAI-compatible format)
        return try parseCompletionResponse(self.allocator, response_body);
    }
};

fn parseCompletionResponse(allocator: std.mem.Allocator, json: []const u8) !http.CompletionResponse {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    const id = try allocator.dupe(u8, obj.get("id").?.string);
    errdefer allocator.free(id);

    const model = try allocator.dupe(u8, obj.get("model").?.string);
    errdefer allocator.free(model);

    const choices = obj.get("choices").?.array.items;
    if (choices.len == 0) return http.ProviderError.InvalidResponse;

    const message = choices[0].object.get("message").?.object;
    const content = try allocator.dupe(u8, message.get("content").?.string);
    errdefer allocator.free(content);

    const finish_reason = if (choices[0].object.get("finish_reason")) |fr|
        try allocator.dupe(u8, fr.string)
    else
        null;

    const usage = if (obj.get("usage")) |usage_obj| blk: {
        const u = usage_obj.object;
        break :blk http.CompletionResponse.Usage{
            .prompt_tokens = @intCast(u.get("prompt_tokens").?.integer),
            .completion_tokens = @intCast(u.get("completion_tokens").?.integer),
            .total_tokens = @intCast(u.get("total_tokens").?.integer),
        };
    } else null;

    return http.CompletionResponse{
        .id = id,
        .model = model,
        .content = content,
        .finish_reason = finish_reason,
        .usage = usage,
    };
}
