//! GitHub Copilot API provider implementation with OAuth device flow
//! Uses OpenAI-compatible API after authentication

const std = @import("std");
const http = @import("http_types.zig");
const vault = @import("../auth/vault.zig");
const oauth = @import("../auth/oauth_device.zig");
const zhttp = @import("zhttp");

const GITHUB_COPILOT_CLIENT_ID = "Iv1.b507a08c87ecfe98"; // Official GitHub Copilot CLI client ID
const DEVICE_CODE_URL = "https://github.com/login/device/code";
const TOKEN_URL = "https://github.com/login/oauth/access_token";
const COPILOT_API_URL = "https://api.githubcopilot.com";

pub const GitHubCopilotProvider = struct {
    allocator: std.mem.Allocator,
    vault_ref: vault.SecretRef,
    access_token: ?[]u8 = null,
    base_url: []const u8 = COPILOT_API_URL,

    pub fn init(allocator: std.mem.Allocator, account: []const u8) GitHubCopilotProvider {
        return .{
            .allocator = allocator,
            .vault_ref = vault.providerSecretRef(.github_copilot, account, .access_token, null),
        };
    }

    pub fn deinit(self: *GitHubCopilotProvider) void {
        if (self.access_token) |token| {
            self.allocator.free(token);
            self.access_token = null;
        }
    }

    pub fn authenticate(self: *GitHubCopilotProvider, vault_instance: *vault.Vault) !void {
        if (self.access_token) |token| {
            self.allocator.free(token);
        }
        self.access_token = try vault_instance.fetch(self.vault_ref);
    }

    /// Perform OAuth device flow authentication
    pub fn authenticateWithDeviceFlow(self: *GitHubCopilotProvider, vault_instance: *vault.Vault) !void {
        var device_flow = oauth.DeviceFlow.init(
            self.allocator,
            GITHUB_COPILOT_CLIENT_ID,
            DEVICE_CODE_URL,
            TOKEN_URL,
        );

        // Request device code
        const device_code_response = try device_flow.requestDeviceCode(null);
        defer device_code_response.deinit(self.allocator);

        // Display instructions to user
        var stdout = std.fs.File.stdout();
        const message = try std.fmt.allocPrint(
            self.allocator,
            "\nGitHub Copilot Authentication\n" ++
                "==============================\n\n" ++
                "Please visit: {s}\n" ++
                "And enter code: {s}\n\n" ++
                "Waiting for authentication...\n",
            .{ device_code_response.verification_uri, device_code_response.user_code },
        );
        defer self.allocator.free(message);
        stdout.writeAll(message) catch {};

        // Poll for token
        const start_time = std.time.timestamp();
        var poll_interval = device_code_response.interval;

        while (true) {
            const elapsed = std.time.timestamp() - start_time;
            if (elapsed > device_code_response.expires_in) {
                return oauth.DeviceFlowError.ExpiredToken;
            }

            std.Thread.sleep(poll_interval * std.time.ns_per_s);

            const token_response = device_flow.pollForToken(device_code_response.device_code) catch |err| switch (err) {
                oauth.DeviceFlowError.AuthorizationPending => continue,
                oauth.DeviceFlowError.SlowDown => {
                    poll_interval += 5; // Increase interval by 5 seconds
                    continue;
                },
                else => return err,
            };

            // Successfully got token - store it
            defer token_response.deinit(self.allocator);

            try vault_instance.store(self.vault_ref, token_response.access_token);

            if (self.access_token) |old_token| {
                self.allocator.free(old_token);
            }
            self.access_token = try self.allocator.dupe(u8, token_response.access_token);

            stdout.writeAll("\n✓ Authentication successful!\n") catch {};
            break;
        }
    }

    pub fn chat(
        self: *GitHubCopilotProvider,
        messages: []const http.Message,
        model: []const u8,
        max_tokens: ?u32,
        temperature: ?f32,
    ) !http.CompletionResponse {
        const access_token = self.access_token orelse return http.ProviderError.AuthenticationFailed;

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
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{access_token});
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
