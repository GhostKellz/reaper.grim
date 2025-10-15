//! OAuth 2.0 Device Authorization Flow implementation
//! Spec: https://datatracker.ietf.org/doc/html/rfc8628

const std = @import("std");
const zhttp = @import("zhttp");

pub const DeviceCodeResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    expires_in: u32,
    interval: u32,

    pub fn deinit(self: DeviceCodeResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.device_code);
        allocator.free(self.user_code);
        allocator.free(self.verification_uri);
    }
};

pub const TokenResponse = struct {
    access_token: []const u8,
    token_type: []const u8,
    scope: []const u8,
    expires_in: ?u32 = null,
    refresh_token: ?[]const u8 = null,

    pub fn deinit(self: TokenResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        allocator.free(self.token_type);
        allocator.free(self.scope);
        if (self.refresh_token) |token| {
            allocator.free(token);
        }
    }
};

pub const DeviceFlowError = error{
    AuthorizationPending,
    SlowDown,
    AccessDenied,
    ExpiredToken,
    InvalidRequest,
    NetworkError,
    ParseError,
};

pub const DeviceFlow = struct {
    allocator: std.mem.Allocator,
    client_id: []const u8,
    device_code_url: []const u8,
    token_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, device_code_url: []const u8, token_url: []const u8) DeviceFlow {
        return .{
            .allocator = allocator,
            .client_id = client_id,
            .device_code_url = device_code_url,
            .token_url = token_url,
        };
    }

    /// Request device and user verification codes
    pub fn requestDeviceCode(self: *DeviceFlow, scope: ?[]const u8) !DeviceCodeResponse {
        var client = zhttp.Client.init(self.allocator, .{});
        defer client.deinit();

        var request = zhttp.Request.init(self.allocator, .POST, self.device_code_url);
        defer request.deinit();

        try request.addHeader("Accept", "application/json");
        try request.addHeader("Content-Type", "application/x-www-form-urlencoded");

        // Build request body
        var body = std.ArrayList(u8){};
        defer body.deinit(self.allocator);

        try body.appendSlice(self.allocator, "client_id=");
        try body.appendSlice(self.allocator, self.client_id);

        if (scope) |s| {
            try body.appendSlice(self.allocator, "&scope=");
            try body.appendSlice(self.allocator, s);
        }

        request.setBody(zhttp.Body.fromString(body.items));

        var response = try client.send(request);
        defer response.deinit();

        if (response.status < 200 or response.status >= 300) {
            return DeviceFlowError.NetworkError;
        }

        const response_body = try response.readAll(10_000_000);
        defer self.allocator.free(response_body);

        return try parseDeviceCodeResponse(self.allocator, response_body);
    }

    /// Poll for access token
    pub fn pollForToken(self: *DeviceFlow, device_code: []const u8) !TokenResponse {
        var client = zhttp.Client.init(self.allocator, .{});
        defer client.deinit();

        var request = zhttp.Request.init(self.allocator, .POST, self.token_url);
        defer request.deinit();

        try request.addHeader("Accept", "application/json");
        try request.addHeader("Content-Type", "application/x-www-form-urlencoded");

        // Build request body
        var body = std.ArrayList(u8){};
        defer body.deinit(self.allocator);

        try body.appendSlice(self.allocator, "client_id=");
        try body.appendSlice(self.allocator, self.client_id);
        try body.appendSlice(self.allocator, "&device_code=");
        try body.appendSlice(self.allocator, device_code);
        try body.appendSlice(self.allocator, "&grant_type=urn:ietf:params:oauth:grant-type:device_code");

        request.setBody(zhttp.Body.fromString(body.items));

        var response = try client.send(request);
        defer response.deinit();

        const response_body = try response.readAll(10_000_000);
        defer self.allocator.free(response_body);

        if (response.status < 200 or response.status >= 300) {
            return parseErrorResponse(response_body);
        }

        return try parseTokenResponse(self.allocator, response_body);
    }
};

fn parseDeviceCodeResponse(allocator: std.mem.Allocator, json: []const u8) !DeviceCodeResponse {
    // Handle chunked transfer encoding
    const json_start = std.mem.indexOfScalar(u8, json, '{') orelse return DeviceFlowError.ParseError;
    const json_end = std.mem.lastIndexOfScalar(u8, json, '}') orelse return DeviceFlowError.ParseError;
    const json_body = json[json_start .. json_end + 1];

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_body, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    const device_code = try allocator.dupe(u8, obj.get("device_code").?.string);
    errdefer allocator.free(device_code);

    const user_code = try allocator.dupe(u8, obj.get("user_code").?.string);
    errdefer allocator.free(user_code);

    const verification_uri = try allocator.dupe(u8, obj.get("verification_uri").?.string);
    errdefer allocator.free(verification_uri);

    const expires_in: u32 = @intCast(obj.get("expires_in").?.integer);
    const interval: u32 = @intCast(obj.get("interval").?.integer);

    return DeviceCodeResponse{
        .device_code = device_code,
        .user_code = user_code,
        .verification_uri = verification_uri,
        .expires_in = expires_in,
        .interval = interval,
    };
}

fn parseTokenResponse(allocator: std.mem.Allocator, json: []const u8) !TokenResponse {
    // Handle chunked transfer encoding
    const json_start = std.mem.indexOfScalar(u8, json, '{') orelse return DeviceFlowError.ParseError;
    const json_end = std.mem.lastIndexOfScalar(u8, json, '}') orelse return DeviceFlowError.ParseError;
    const json_body = json[json_start .. json_end + 1];

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_body, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    const access_token = try allocator.dupe(u8, obj.get("access_token").?.string);
    errdefer allocator.free(access_token);

    const token_type = try allocator.dupe(u8, obj.get("token_type").?.string);
    errdefer allocator.free(token_type);

    const scope = try allocator.dupe(u8, obj.get("scope").?.string);
    errdefer allocator.free(scope);

    const expires_in = if (obj.get("expires_in")) |exp| @as(u32, @intCast(exp.integer)) else null;

    const refresh_token = if (obj.get("refresh_token")) |rt|
        try allocator.dupe(u8, rt.string)
    else
        null;

    return TokenResponse{
        .access_token = access_token,
        .token_type = token_type,
        .scope = scope,
        .expires_in = expires_in,
        .refresh_token = refresh_token,
    };
}

fn parseErrorResponse(json: []const u8) DeviceFlowError {
    // Handle chunked transfer encoding
    const json_start = std.mem.indexOfScalar(u8, json, '{') orelse return DeviceFlowError.ParseError;
    const json_end = std.mem.lastIndexOfScalar(u8, json, '}') orelse return DeviceFlowError.ParseError;
    const json_body = json[json_start .. json_end + 1];

    // Simple error detection without full parsing
    if (std.mem.indexOf(u8, json_body, "authorization_pending") != null) {
        return DeviceFlowError.AuthorizationPending;
    }
    if (std.mem.indexOf(u8, json_body, "slow_down") != null) {
        return DeviceFlowError.SlowDown;
    }
    if (std.mem.indexOf(u8, json_body, "access_denied") != null) {
        return DeviceFlowError.AccessDenied;
    }
    if (std.mem.indexOf(u8, json_body, "expired_token") != null) {
        return DeviceFlowError.ExpiredToken;
    }

    return DeviceFlowError.InvalidRequest;
}
