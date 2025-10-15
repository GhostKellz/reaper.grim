//! Anthropic Claude API provider implementation.

const std = @import("std");
const http = @import("http_types.zig");
const vault = @import("../auth/vault.zig");
const zhttp = @import("zhttp");

pub const ClaudeProvider = struct {
    allocator: std.mem.Allocator,
    vault_ref: vault.SecretRef,
    api_key: ?[]u8 = null,
    base_url: []const u8 = "https://api.anthropic.com/v1",
    anthropic_version: []const u8 = "2023-06-01",

    pub fn init(allocator: std.mem.Allocator, account: []const u8) ClaudeProvider {
        return .{
            .allocator = allocator,
            .vault_ref = vault.providerSecretRef(.anthropic, account, .api_key, null),
        };
    }

    pub fn deinit(self: *ClaudeProvider) void {
        if (self.api_key) |key| {
            self.allocator.free(key);
            self.api_key = null;
        }
    }

    pub fn authenticate(self: *ClaudeProvider, vault_instance: *vault.Vault) !void {
        if (self.api_key) |key| {
            self.allocator.free(key);
        }
        self.api_key = try vault_instance.fetch(self.vault_ref);
    }

    pub fn chat(
        self: *ClaudeProvider,
        messages: []const http.Message,
        model: []const u8,
        max_tokens: ?u32,
        temperature: ?f32,
    ) !http.CompletionResponse {
        const api_key = self.api_key orelse return http.ProviderError.AuthenticationFailed;

        // Build request JSON
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

        // max_tokens is required for Anthropic
        const tokens = max_tokens orelse 4096;
        const tokens_str = try std.fmt.allocPrint(self.allocator, ",\"max_tokens\":{d}", .{tokens});
        defer self.allocator.free(tokens_str);
        try request_json.appendSlice(self.allocator, tokens_str);

        if (temperature) |temp| {
            const temp_str = try std.fmt.allocPrint(self.allocator, ",\"temperature\":{d}", .{temp});
            defer self.allocator.free(temp_str);
            try request_json.appendSlice(self.allocator, temp_str);
        }

        try request_json.appendSlice(self.allocator, "}");

        // Build auth header
        const auth_header = try std.fmt.allocPrint(self.allocator, "{s}", .{api_key});
        defer self.allocator.free(auth_header);

        // Build URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/messages", .{self.base_url});
        defer self.allocator.free(url);

        // Make request (Anthropic uses x-api-key header, need custom version)
        const response_body = try self.makeAnthropicRequest(url, request_json.items);
        defer self.allocator.free(response_body);

        // Parse response
        return try parseClaudeResponse(self.allocator, response_body);
    }

    fn makeAnthropicRequest(self: *ClaudeProvider, url: []const u8, body_json: []const u8) ![]u8 {
        const api_key = self.api_key orelse return http.ProviderError.AuthenticationFailed;

        var client = zhttp.Client.init(self.allocator, .{});
        defer client.deinit();

        var request = zhttp.Request.init(self.allocator, .POST, url);
        defer request.deinit();

        try request.addHeader("Content-Type", "application/json");
        try request.addHeader("x-api-key", api_key);
        try request.addHeader("anthropic-version", self.anthropic_version);

        request.setBody(zhttp.Body.fromString(body_json));

        var response = try client.send(request);
        defer response.deinit();

        if (response.status < 200 or response.status >= 300) {
            return mapHttpError(response.status);
        }

        return try response.readAll(10_000_000); // 10MB max
    }
};

fn parseClaudeResponse(allocator: std.mem.Allocator, json: []const u8) !http.CompletionResponse {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    const id = try allocator.dupe(u8, obj.get("id").?.string);
    errdefer allocator.free(id);

    const model = try allocator.dupe(u8, obj.get("model").?.string);
    errdefer allocator.free(model);

    const content_array = obj.get("content").?.array.items;
    if (content_array.len == 0) return http.ProviderError.InvalidResponse;

    const text_block = content_array[0].object;
    const content = try allocator.dupe(u8, text_block.get("text").?.string);
    errdefer allocator.free(content);

    const finish_reason = if (obj.get("stop_reason")) |sr|
        try allocator.dupe(u8, sr.string)
    else
        null;

    const usage = if (obj.get("usage")) |usage_obj| blk: {
        const u = usage_obj.object;
        break :blk http.CompletionResponse.Usage{
            .prompt_tokens = @intCast(u.get("input_tokens").?.integer),
            .completion_tokens = @intCast(u.get("output_tokens").?.integer),
            .total_tokens = @intCast(u.get("input_tokens").?.integer + u.get("output_tokens").?.integer),
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

fn mapHttpError(status_code: u16) http.ProviderError {
    return switch (status_code) {
        401, 403 => http.ProviderError.AuthenticationFailed,
        429 => http.ProviderError.RateLimited,
        400...499 => http.ProviderError.InvalidRequest,
        500...599 => http.ProviderError.ServerError,
        else => http.ProviderError.NetworkError,
    };
}
