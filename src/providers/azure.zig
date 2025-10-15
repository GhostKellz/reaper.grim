//! Azure OpenAI API provider implementation.
//! Note: Azure OpenAI uses a different endpoint structure than standard OpenAI.

const std = @import("std");
const http = @import("http_types.zig");
const vault = @import("../auth/vault.zig");
const zhttp = @import("zhttp");

pub const AzureOpenAIProvider = struct {
    allocator: std.mem.Allocator,
    vault_ref: vault.SecretRef,
    api_key: ?[]u8 = null,
    endpoint: []const u8, // e.g., "https://your-resource.openai.azure.com"
    deployment: []const u8, // e.g., "gpt-4"
    api_version: []const u8 = "2024-02-15-preview",

    pub fn init(allocator: std.mem.Allocator, account: []const u8, endpoint: []const u8, deployment: []const u8) AzureOpenAIProvider {
        return .{
            .allocator = allocator,
            .vault_ref = vault.providerSecretRef(.azure_openai, account, .api_key, null),
            .endpoint = endpoint,
            .deployment = deployment,
        };
    }

    pub fn deinit(self: *AzureOpenAIProvider) void {
        if (self.api_key) |key| {
            self.allocator.free(key);
            self.api_key = null;
        }
    }

    pub fn authenticate(self: *AzureOpenAIProvider, vault_instance: *vault.Vault) !void {
        if (self.api_key) |key| {
            self.allocator.free(key);
        }
        self.api_key = try vault_instance.fetch(self.vault_ref);
    }

    pub fn chat(
        self: *AzureOpenAIProvider,
        messages: []const http.Message,
        model: []const u8, // This parameter is ignored for Azure; deployment is used instead
        max_tokens: ?u32,
        temperature: ?f32,
    ) !http.CompletionResponse {
        _ = model; // Azure uses deployment name, not model parameter
        const api_key = self.api_key orelse return http.ProviderError.AuthenticationFailed;

        // Build request JSON (OpenAI-compatible format)
        var request_json = std.ArrayList(u8){};
        defer request_json.deinit(self.allocator);

        try request_json.appendSlice(self.allocator, "{\"messages\":[");

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

        // Build auth header (Azure uses api-key header)
        const auth_header = try std.fmt.allocPrint(self.allocator, "{s}", .{api_key});
        defer self.allocator.free(auth_header);

        // Build Azure-specific URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/openai/deployments/{s}/chat/completions?api-version={s}",
            .{ self.endpoint, self.deployment, self.api_version },
        );
        defer self.allocator.free(url);

        // Make request with Azure-specific headers
        const response_body = try self.makeAzureRequest(url, request_json.items);
        defer self.allocator.free(response_body);

        // Parse response (uses OpenAI-compatible format)
        return try parseCompletionResponse(self.allocator, response_body);
    }

    fn makeAzureRequest(self: *AzureOpenAIProvider, url: []const u8, body_json: []const u8) ![]u8 {
        const api_key = self.api_key orelse return http.ProviderError.AuthenticationFailed;

        var client = zhttp.Client.init(self.allocator, .{});
        defer client.deinit();

        var request = zhttp.Request.init(self.allocator, .POST, url);
        defer request.deinit();

        try request.addHeader("Content-Type", "application/json");
        try request.addHeader("api-key", api_key);

        request.setBody(zhttp.Body.fromString(body_json));

        var response = try client.send(request);
        defer response.deinit();

        if (response.status < 200 or response.status >= 300) {
            return mapHttpError(response.status);
        }

        return try response.readAll(10_000_000); // 10MB max
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

fn mapHttpError(status_code: u16) http.ProviderError {
    return switch (status_code) {
        401, 403 => http.ProviderError.AuthenticationFailed,
        429 => http.ProviderError.RateLimited,
        400...499 => http.ProviderError.InvalidRequest,
        500...599 => http.ProviderError.ServerError,
        else => http.ProviderError.NetworkError,
    };
}
