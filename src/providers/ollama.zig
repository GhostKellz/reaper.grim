//! Ollama local LLM provider implementation.
//! Ollama uses an OpenAI-compatible API but runs locally.

const std = @import("std");
const http = @import("http_types.zig");
const vault = @import("../auth/vault.zig");
const zhttp = @import("zhttp");

pub const OllamaProvider = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8 = "http://localhost:11434/v1",
    // Ollama doesn't require authentication by default

    pub fn init(allocator: std.mem.Allocator, base_url: ?[]const u8) OllamaProvider {
        return .{
            .allocator = allocator,
            .base_url = base_url orelse "http://localhost:11434/v1",
        };
    }

    pub fn deinit(self: *OllamaProvider) void {
        _ = self;
        // No cleanup needed for Ollama
    }

    pub fn authenticate(self: *OllamaProvider, vault_instance: *vault.Vault) !void {
        _ = self;
        _ = vault_instance;
        // Ollama doesn't require authentication
    }

    pub fn chat(
        self: *OllamaProvider,
        messages: []const http.Message,
        model: []const u8,
        max_tokens: ?u32,
        temperature: ?f32,
    ) !http.CompletionResponse {
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

        // Build URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url});
        defer self.allocator.free(url);

        // Make request (no auth needed)
        const response_body = try self.makeOllamaRequest(url, request_json.items);
        defer self.allocator.free(response_body);

        // Parse response (uses OpenAI-compatible format)
        return try parseCompletionResponse(self.allocator, response_body);
    }

    fn makeOllamaRequest(self: *OllamaProvider, url: []const u8, body_json: []const u8) ![]u8 {
        var client = zhttp.Client.init(self.allocator, .{});
        defer client.deinit();

        var request = zhttp.Request.init(self.allocator, .POST, url);
        defer request.deinit();

        try request.addHeader("Content-Type", "application/json");

        request.setBody(zhttp.Body.fromString(body_json));

        var response = try client.send(request);
        defer response.deinit();

        if (response.status < 200 or response.status >= 300) {
            return mapHttpError(response.status);
        }

        return try response.readAll(10_000_000); // 10MB max
    }

    /// List all models available in the Ollama instance
    pub fn listModels(self: *OllamaProvider) ![][]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "http://localhost:11434/api/tags", .{});
        defer self.allocator.free(url);

        var client = zhttp.Client.init(self.allocator, .{});
        defer client.deinit();

        var request = zhttp.Request.init(self.allocator, .GET, url);
        defer request.deinit();

        var response = try client.send(request);
        defer response.deinit();

        if (response.status < 200 or response.status >= 300) {
            return http.ProviderError.NetworkError;
        }

        const body = try response.readAll(10_000_000); // 10MB max
        defer self.allocator.free(body);

        // Handle chunked transfer encoding: find first '{' and last '}'
        const json_start = std.mem.indexOfScalar(u8, body, '{') orelse return http.ProviderError.InvalidResponse;
        const json_end = std.mem.lastIndexOfScalar(u8, body, '}') orelse return http.ProviderError.InvalidResponse;
        const json_body = body[json_start .. json_end + 1];

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_body, .{});
        defer parsed.deinit();

        const models_array = parsed.value.object.get("models").?.array.items;
        var model_names = std.ArrayList([]const u8){};

        for (models_array) |model_obj| {
            const name = try self.allocator.dupe(u8, model_obj.object.get("name").?.string);
            try model_names.append(self.allocator, name);
        }

        const result = try model_names.toOwnedSlice(self.allocator);
        model_names.deinit(self.allocator);
        return result;
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
        400, 402, 404...428, 430...499 => http.ProviderError.InvalidRequest,
        500...599 => http.ProviderError.ServerError,
        else => http.ProviderError.NetworkError,
    };
}
