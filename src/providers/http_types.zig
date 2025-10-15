//! Shared HTTP types and utilities for all API providers.

const std = @import("std");
const zhttp = @import("zhttp");

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const CompletionRequest = struct {
    model: []const u8,
    prompt: ?[]const u8 = null,
    messages: ?[]const Message = null,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    stream: bool = false,
};

pub const CompletionResponse = struct {
    id: []const u8,
    model: []const u8,
    content: []const u8,
    finish_reason: ?[]const u8 = null,
    usage: ?Usage = null,

    pub const Usage = struct {
        prompt_tokens: u32,
        completion_tokens: u32,
        total_tokens: u32,
    };

    pub fn deinit(self: *CompletionResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.model);
        allocator.free(self.content);
        if (self.finish_reason) |reason| allocator.free(reason);
    }
};

pub const StreamChunk = struct {
    id: []const u8,
    model: []const u8,
    delta: []const u8, // Content delta (token or partial text)
    finish_reason: ?[]const u8 = null,
    is_final: bool = false,

    pub fn deinit(self: *StreamChunk, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.model);
        allocator.free(self.delta);
        if (self.finish_reason) |reason| allocator.free(reason);
    }
};

/// Callback function for handling streaming chunks
/// Return false to stop streaming, true to continue
pub const StreamCallback = *const fn (chunk: StreamChunk) bool;

pub const ProviderError = error{
    AuthenticationFailed,
    RateLimited,
    InvalidRequest,
    ServerError,
    NetworkError,
    InvalidResponse,
};

pub fn makeJsonRequest(
    allocator: std.mem.Allocator,
    method: zhttp.Method,
    url: []const u8,
    auth_header: []const u8,
    body_json: ?[]const u8,
) ![]u8 {
    var client = zhttp.Client.init(allocator, .{});
    defer client.deinit();

    var request = zhttp.Request.init(allocator, method, url);
    defer request.deinit();

    try request.addHeader("Content-Type", "application/json");
    try request.addHeader("Authorization", auth_header);

    if (body_json) |json| {
        request.setBody(zhttp.Body.fromString(json));
    }

    var response = try client.send(request);
    defer response.deinit();

    if (response.status < 200 or response.status >= 300) {
        return mapHttpError(response.status);
    }

    return try response.readAll(10_000_000); // 10MB max
}

fn mapHttpError(status_code: u16) ProviderError {
    return switch (status_code) {
        401, 403 => ProviderError.AuthenticationFailed,
        429 => ProviderError.RateLimited,
        400...499 => ProviderError.InvalidRequest,
        500...599 => ProviderError.ServerError,
        else => ProviderError.NetworkError,
    };
}
