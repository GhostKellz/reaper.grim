# Reaper.grim ⚡ HTTP Integration

**Using zhttp for AI Provider APIs, OAuth, and Streaming**

---

## 🎯 Overview

**zhttp** is Reaper.grim's HTTP client library for all external communication:
- 🤖 **AI Provider APIs** - OpenAI, Claude, Ollama, Copilot
- 🔐 **OAuth Flows** - Google Sign-In (Claude), GitHub Sign-In (Copilot)
- ⚡ **HTTP/3** - Modern QUIC transport for speed
- 📡 **Streaming** - Server-Sent Events (SSE) for real-time responses
- 🔄 **Retries** - Automatic retry with exponential backoff

**Why zhttp over std.http?**
- ✅ **HTTP/3 support** - QUIC transport via zquic
- ✅ **Connection pooling** - Reuse connections across requests
- ✅ **Better streaming** - Native SSE and chunked encoding
- ✅ **Async runtime** - Integrates with zsync
- ✅ **Pure Zig** - No C dependencies

---

## 🏗️ Architecture

### HTTP Communication in Reaper

```
┌─────────────────────────────────────────────────────────┐
│                  Reaper.grim Daemon                      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  HTTP Client Layer (zhttp)                         │ │
│  │                                                     │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐│ │
│  │  │ AI Provider │  │    OAuth    │  │  Streaming  ││ │
│  │  │   Client    │  │   Client    │  │   Client    ││ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘│ │
│  │         │                │                │        │ │
│  │         └────────────────┴────────────────┘        │ │
│  │                      │                              │ │
│  │              ┌───────▼───────┐                     │ │
│  │              │  Connection   │                     │ │
│  │              │     Pool      │                     │ │
│  │              └───────┬───────┘                     │ │
│  │                      │                              │ │
│  │         ┌────────────┴────────────┐                │ │
│  │         │                         │                │ │
│  │    ┌────▼─────┐            ┌─────▼────┐           │ │
│  │    │  HTTP/3  │            │ HTTP/1.1 │           │ │
│  │    │  (QUIC)  │            │ Fallback │           │ │
│  │    └──────────┘            └──────────┘           │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                         │
                         │ HTTPS/QUIC
                         │
        ┌────────────────┴────────────────┐
        │                                  │
   ┌────▼─────┐                      ┌────▼─────┐
   │  OpenAI  │                      │  Claude  │
   │    API   │                      │   API    │
   └──────────┘                      └──────────┘
        │                                  │
   ┌────▼─────┐                      ┌────▼─────┐
   │  GitHub  │                      │  Google  │
   │  Copilot │                      │  OAuth   │
   └──────────┘                      └──────────┘
```

---

## 🚀 Installation

Add zhttp and zquic to `build.zig.zon` (main refs archive prefered):

```zig
.dependencies = .{
    .zhttp = .{
        .url = "https://github.com/ghostkellz/zhttp/archive/{COMMIT}.tar.gz",
        .hash = "...",
    },
    .zquic = .{
        .url = "https://github.com/ghostkellz/zquic/archive/{COMMIT}.tar.gz",
        .hash = "...",
    },
    .zsync = .{
        .url = "https://github.com/ghostkellz/zsync/archive/{COMMIT}.tar.gz",
        .hash = "...",
    },
},
```

---

## 🤖 AI Provider Integration

### 1. OpenAI API Client

**`src/providers/openai.zig`** - OpenAI API integration:

```zig
const std = @import("std");
const zhttp = @import("zhttp");
const zsync = @import("zsync");

pub const OpenAIClient = struct {
    allocator: std.mem.Allocator,
    http: *zhttp.Client,
    api_key: []const u8,
    base_url: []const u8 = "https://api.openai.com/v1",

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !*OpenAIClient {
        var self = try allocator.create(OpenAIClient);
        self.allocator = allocator;
        self.api_key = api_key;

        // Create HTTP client with HTTP/3 preferred
        self.http = try zhttp.Client.init(allocator, .{
            .protocol = .http3, // Prefer HTTP/3 (QUIC)
            .fallback = .http1, // Fallback to HTTP/1.1
            .connect_timeout = 10000, // 10s
            .read_timeout = 120000,   // 2min for long completions
            .max_retries = 3,
            .pool = .{
                .max_per_host = 5,
                .max_total = 20,
            },
        });

        return self;
    }

    /// Request completion (streaming)
    pub fn complete(
        self: *OpenAIClient,
        request: CompletionRequest,
        callback: *const fn ([]const u8) void,
    ) !CompletionResponse {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/chat/completions",
            .{self.base_url},
        );
        defer self.allocator.free(url);

        // Build request body
        const body = try std.json.stringifyAlloc(self.allocator, .{
            .model = request.model,
            .messages = request.messages,
            .temperature = request.temperature,
            .max_tokens = request.max_tokens,
            .stream = true, // Enable streaming
        }, .{});
        defer self.allocator.free(body);

        // Create HTTP request
        const http_request = try zhttp.RequestBuilder.init(
            self.allocator,
            .POST,
            url,
        )
            .header("Authorization", try std.fmt.allocPrint(
                self.allocator,
                "Bearer {s}",
                .{self.api_key},
            ))
            .header("Content-Type", "application/json")
            .body(zhttp.Body{ .text = body })
            .timeout(120000) // 2min
            .build();
        defer http_request.deinit();

        // Send request and stream response
        var response = try self.http.send(http_request);
        defer response.deinit();

        if (!response.isSuccess()) {
            const error_body = try response.text(4096);
            defer self.allocator.free(error_body);
            std.log.err("OpenAI API error: {s}", .{error_body});
            return error.ApiError;
        }

        // Parse SSE stream
        var full_text = std.ArrayList(u8).init(self.allocator);
        defer full_text.deinit();

        var sse_reader = zhttp.SSEReader.init(response.body_reader);
        while (try sse_reader.next()) |event| {
            defer event.deinit();

            if (std.mem.eql(u8, event.data, "[DONE]")) break;

            // Parse JSON chunk
            const parsed = try std.json.parseFromSlice(
                StreamChunk,
                self.allocator,
                event.data,
                .{},
            );
            defer parsed.deinit();

            const delta = parsed.value.choices[0].delta.content orelse continue;
            try full_text.appendSlice(delta);

            // Callback with partial text
            callback(delta);
        }

        return CompletionResponse{
            .text = try full_text.toOwnedSlice(),
            .model = request.model,
        };
    }

    pub fn deinit(self: *OpenAIClient) void {
        self.http.deinit();
        self.allocator.destroy(self);
    }
};

pub const CompletionRequest = struct {
    model: []const u8 = "gpt-4",
    messages: []const Message,
    temperature: f32 = 0.7,
    max_tokens: ?u32 = null,
};

pub const Message = struct {
    role: []const u8, // "system", "user", "assistant"
    content: []const u8,
};

pub const CompletionResponse = struct {
    text: []const u8,
    model: []const u8,
};

const StreamChunk = struct {
    choices: []struct {
        delta: struct {
            content: ?[]const u8,
        },
    },
};
```

### 2. Claude API Client

**`src/providers/claude.zig`** - Anthropic Claude API:

```zig
const std = @import("std");
const zhttp = @import("zhttp");

pub const ClaudeClient = struct {
    allocator: std.mem.Allocator,
    http: *zhttp.Client,
    api_key: []const u8,
    base_url: []const u8 = "https://api.anthropic.com/v1",

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !*ClaudeClient {
        var self = try allocator.create(ClaudeClient);
        self.allocator = allocator;
        self.api_key = api_key;

        self.http = try zhttp.Client.init(allocator, .{
            .protocol = .http3,
            .fallback = .http1,
            .connect_timeout = 10000,
            .read_timeout = 300000, // 5min for complex tasks
        });

        return self;
    }

    /// Request completion with streaming
    pub fn complete(
        self: *ClaudeClient,
        request: CompletionRequest,
        callback: *const fn ([]const u8) void,
    ) !CompletionResponse {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/messages",
            .{self.base_url},
        );
        defer self.allocator.free(url);

        const body = try std.json.stringifyAlloc(self.allocator, .{
            .model = request.model,
            .messages = request.messages,
            .max_tokens = request.max_tokens orelse 4096,
            .stream = true,
        }, .{});
        defer self.allocator.free(body);

        const http_request = try zhttp.RequestBuilder.init(
            self.allocator,
            .POST,
            url,
        )
            .header("x-api-key", self.api_key)
            .header("anthropic-version", "2023-06-01")
            .header("Content-Type", "application/json")
            .body(zhttp.Body{ .text = body })
            .build();
        defer http_request.deinit();

        var response = try self.http.send(http_request);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.ApiError;
        }

        // Stream response
        var full_text = std.ArrayList(u8).init(self.allocator);
        defer full_text.deinit();

        var sse_reader = zhttp.SSEReader.init(response.body_reader);
        while (try sse_reader.next()) |event| {
            defer event.deinit();

            if (std.mem.eql(u8, event.event_type, "message_stop")) break;

            if (std.mem.eql(u8, event.event_type, "content_block_delta")) {
                const parsed = try std.json.parseFromSlice(
                    ContentDelta,
                    self.allocator,
                    event.data,
                    .{},
                );
                defer parsed.deinit();

                const delta = parsed.value.delta.text;
                try full_text.appendSlice(delta);
                callback(delta);
            }
        }

        return CompletionResponse{
            .text = try full_text.toOwnedSlice(),
            .model = request.model,
        };
    }

    pub fn deinit(self: *ClaudeClient) void {
        self.http.deinit();
        self.allocator.destroy(self);
    }
};

pub const CompletionRequest = struct {
    model: []const u8 = "claude-sonnet-4-5",
    messages: []const Message,
    max_tokens: ?u32 = null,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const CompletionResponse = struct {
    text: []const u8,
    model: []const u8,
};

const ContentDelta = struct {
    delta: struct {
        text: []const u8,
    },
};
```

### 3. GitHub Copilot Client

**`src/providers/copilot.zig`** - GitHub Copilot API:

```zig
const std = @import("std");
const zhttp = @import("zhttp");

pub const CopilotClient = struct {
    allocator: std.mem.Allocator,
    http: *zhttp.Client,
    access_token: []const u8,
    base_url: []const u8 = "https://api.githubcopilot.com",

    pub fn init(allocator: std.mem.Allocator, access_token: []const u8) !*CopilotClient {
        var self = try allocator.create(CopilotClient);
        self.allocator = allocator;
        self.access_token = access_token;

        // Copilot needs fast response (<100ms target)
        self.http = try zhttp.Client.init(allocator, .{
            .protocol = .http3, // HTTP/3 for speed
            .connect_timeout = 5000,
            .read_timeout = 10000, // 10s max
            .pool = .{
                .max_per_host = 10, // More connections for parallelism
                .max_total = 50,
            },
        });

        return self;
    }

    /// Request fast completion (<100ms target)
    pub fn complete(
        self: *CopilotClient,
        request: CompletionRequest,
    ) !CompletionResponse {
        const start = std.time.milliTimestamp();

        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/completions",
            .{self.base_url},
        );
        defer self.allocator.free(url);

        const body = try std.json.stringifyAlloc(self.allocator, .{
            .prompt = request.prompt,
            .suffix = request.suffix,
            .language = request.language,
            .max_tokens = 100,
        }, .{});
        defer self.allocator.free(body);

        const http_request = try zhttp.RequestBuilder.init(
            self.allocator,
            .POST,
            url,
        )
            .header("Authorization", try std.fmt.allocPrint(
                self.allocator,
                "Bearer {s}",
                .{self.access_token},
            ))
            .header("Content-Type", "application/json")
            .body(zhttp.Body{ .text = body })
            .timeout(10000)
            .build();
        defer http_request.deinit();

        var response = try self.http.send(http_request);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.ApiError;
        }

        const response_body = try response.text(8192);
        defer self.allocator.free(response_body);

        const parsed = try std.json.parseFromSlice(
            CopilotResponse,
            self.allocator,
            response_body,
            .{},
        );
        defer parsed.deinit();

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start));

        return CompletionResponse{
            .text = try self.allocator.dupe(u8, parsed.value.choices[0].text),
            .latency_ms = latency,
        };
    }

    pub fn deinit(self: *CopilotClient) void {
        self.http.deinit();
        self.allocator.destroy(self);
    }
};

pub const CompletionRequest = struct {
    prompt: []const u8,
    suffix: []const u8,
    language: []const u8,
};

pub const CompletionResponse = struct {
    text: []const u8,
    latency_ms: u32,
};

const CopilotResponse = struct {
    choices: []struct {
        text: []const u8,
    },
};
```

### 4. Ollama Client (Local)

**`src/providers/ollama.zig`** - Local Ollama API:

```zig
const std = @import("std");
const zhttp = @import("zhttp");

pub const OllamaClient = struct {
    allocator: std.mem.Allocator,
    http: *zhttp.Client,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) !*OllamaClient {
        var self = try allocator.create(OllamaClient);
        self.allocator = allocator;
        self.base_url = base_url;

        // Local server, HTTP/1.1 is fine
        self.http = try zhttp.Client.init(allocator, .{
            .protocol = .http1,
            .connect_timeout = 5000,
            .read_timeout = 60000,
        });

        return self;
    }

    pub fn complete(
        self: *OllamaClient,
        request: CompletionRequest,
        callback: *const fn ([]const u8) void,
    ) !CompletionResponse {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/generate",
            .{self.base_url},
        );
        defer self.allocator.free(url);

        const body = try std.json.stringifyAlloc(self.allocator, .{
            .model = request.model,
            .prompt = request.prompt,
            .stream = true,
        }, .{});
        defer self.allocator.free(body);

        const http_request = try zhttp.RequestBuilder.init(
            self.allocator,
            .POST,
            url,
        )
            .header("Content-Type", "application/json")
            .body(zhttp.Body{ .text = body })
            .build();
        defer http_request.deinit();

        var response = try self.http.send(http_request);
        defer response.deinit();

        var full_text = std.ArrayList(u8).init(self.allocator);
        defer full_text.deinit();

        // Ollama streams newline-delimited JSON
        var reader = response.body_reader;
        var buffer: [4096]u8 = undefined;

        while (true) {
            const line = try reader.readUntilDelimiterOrEof(&buffer, '\n') orelse break;

            const parsed = try std.json.parseFromSlice(
                OllamaChunk,
                self.allocator,
                line,
                .{},
            );
            defer parsed.deinit();

            try full_text.appendSlice(parsed.value.response);
            callback(parsed.value.response);

            if (parsed.value.done) break;
        }

        return CompletionResponse{
            .text = try full_text.toOwnedSlice(),
            .model = request.model,
        };
    }

    pub fn deinit(self: *OllamaClient) void {
        self.http.deinit();
        self.allocator.destroy(self);
    }
};

pub const CompletionRequest = struct {
    model: []const u8,
    prompt: []const u8,
};

pub const CompletionResponse = struct {
    text: []const u8,
    model: []const u8,
};

const OllamaChunk = struct {
    response: []const u8,
    done: bool,
};
```

---

## 🔐 OAuth Integration

### 1. Google OAuth (Claude Code Max)

**`src/auth/google_oauth.zig`** - Google Sign-In flow:

```zig
const std = @import("std");
const zhttp = @import("zhttp");

pub const GoogleOAuth = struct {
    allocator: std.mem.Allocator,
    http: *zhttp.Client,
    client_id: []const u8,
    client_secret: []const u8,
    redirect_uri: []const u8 = "http://localhost:8080/callback",

    pub fn init(
        allocator: std.mem.Allocator,
        client_id: []const u8,
        client_secret: []const u8,
    ) !*GoogleOAuth {
        var self = try allocator.create(GoogleOAuth);
        self.allocator = allocator;
        self.client_id = client_id;
        self.client_secret = client_secret;

        self.http = try zhttp.Client.init(allocator, .{
            .protocol = .http3,
            .fallback = .http1,
        });

        return self;
    }

    /// Generate authorization URL
    pub fn getAuthUrl(self: *GoogleOAuth) ![]const u8 {
        const scopes = "openid email profile";
        return try std.fmt.allocPrint(
            self.allocator,
            "https://accounts.google.com/o/oauth2/v2/auth?" ++
            "client_id={s}&" ++
            "redirect_uri={s}&" ++
            "response_type=code&" ++
            "scope={s}&" ++
            "access_type=offline",
            .{
                self.client_id,
                self.redirect_uri,
                scopes,
            },
        );
    }

    /// Exchange authorization code for tokens
    pub fn exchangeCode(self: *GoogleOAuth, code: []const u8) !TokenResponse {
        const url = "https://oauth2.googleapis.com/token";

        const body = try std.fmt.allocPrint(
            self.allocator,
            "code={s}&" ++
            "client_id={s}&" ++
            "client_secret={s}&" ++
            "redirect_uri={s}&" ++
            "grant_type=authorization_code",
            .{
                code,
                self.client_id,
                self.client_secret,
                self.redirect_uri,
            },
        );
        defer self.allocator.free(body);

        const request = try zhttp.RequestBuilder.init(
            self.allocator,
            .POST,
            url,
        )
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(zhttp.Body{ .text = body })
            .build();
        defer request.deinit();

        var response = try self.http.send(request);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.OAuthError;
        }

        const response_body = try response.text(4096);
        defer self.allocator.free(response_body);

        const parsed = try std.json.parseFromSlice(
            TokenResponse,
            self.allocator,
            response_body,
            .{},
        );
        defer parsed.deinit();

        return TokenResponse{
            .access_token = try self.allocator.dupe(u8, parsed.value.access_token),
            .refresh_token = if (parsed.value.refresh_token) |rt|
                try self.allocator.dupe(u8, rt)
            else
                null,
            .expires_in = parsed.value.expires_in,
        };
    }

    /// Refresh access token
    pub fn refreshToken(self: *GoogleOAuth, refresh_token: []const u8) !TokenResponse {
        const url = "https://oauth2.googleapis.com/token";

        const body = try std.fmt.allocPrint(
            self.allocator,
            "refresh_token={s}&" ++
            "client_id={s}&" ++
            "client_secret={s}&" ++
            "grant_type=refresh_token",
            .{
                refresh_token,
                self.client_id,
                self.client_secret,
            },
        );
        defer self.allocator.free(body);

        const request = try zhttp.RequestBuilder.init(
            self.allocator,
            .POST,
            url,
        )
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(zhttp.Body{ .text = body })
            .build();
        defer request.deinit();

        var response = try self.http.send(request);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.RefreshError;
        }

        const response_body = try response.text(4096);
        defer self.allocator.free(response_body);

        const parsed = try std.json.parseFromSlice(
            TokenResponse,
            self.allocator,
            response_body,
            .{},
        );
        defer parsed.deinit();

        return TokenResponse{
            .access_token = try self.allocator.dupe(u8, parsed.value.access_token),
            .refresh_token = try self.allocator.dupe(u8, refresh_token), // Keep existing
            .expires_in = parsed.value.expires_in,
        };
    }

    pub fn deinit(self: *GoogleOAuth) void {
        self.http.deinit();
        self.allocator.destroy(self);
    }
};

pub const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8,
    expires_in: u32,
};
```

### 2. GitHub OAuth (Copilot)

**`src/auth/github_oauth.zig`** - GitHub Sign-In flow:

```zig
const std = @import("std");
const zhttp = @import("zhttp");

pub const GitHubOAuth = struct {
    allocator: std.mem.Allocator,
    http: *zhttp.Client,
    client_id: []const u8,
    client_secret: []const u8,
    redirect_uri: []const u8 = "http://localhost:8080/callback",

    pub fn init(
        allocator: std.mem.Allocator,
        client_id: []const u8,
        client_secret: []const u8,
    ) !*GitHubOAuth {
        var self = try allocator.create(GitHubOAuth);
        self.allocator = allocator;
        self.client_id = client_id;
        self.client_secret = client_secret;

        self.http = try zhttp.Client.init(allocator, .{
            .protocol = .http3,
            .fallback = .http1,
        });

        return self;
    }

    pub fn getAuthUrl(self: *GitHubOAuth) ![]const u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "https://github.com/login/oauth/authorize?" ++
            "client_id={s}&" ++
            "redirect_uri={s}&" ++
            "scope=user:email copilot",
            .{
                self.client_id,
                self.redirect_uri,
            },
        );
    }

    pub fn exchangeCode(self: *GitHubOAuth, code: []const u8) !TokenResponse {
        const url = "https://github.com/login/oauth/access_token";

        const body = try std.json.stringifyAlloc(self.allocator, .{
            .client_id = self.client_id,
            .client_secret = self.client_secret,
            .code = code,
        }, .{});
        defer self.allocator.free(body);

        const request = try zhttp.RequestBuilder.init(
            self.allocator,
            .POST,
            url,
        )
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .body(zhttp.Body{ .text = body })
            .build();
        defer request.deinit();

        var response = try self.http.send(request);
        defer response.deinit();

        const response_body = try response.text(4096);
        defer self.allocator.free(response_body);

        const parsed = try std.json.parseFromSlice(
            TokenResponse,
            self.allocator,
            response_body,
            .{},
        );
        defer parsed.deinit();

        return TokenResponse{
            .access_token = try self.allocator.dupe(u8, parsed.value.access_token),
        };
    }

    pub fn deinit(self: *GitHubOAuth) void {
        self.http.deinit();
        self.allocator.destroy(self);
    }
};

pub const TokenResponse = struct {
    access_token: []const u8,
};
```

---

## ⚡ HTTP/3 & QUIC

**Why HTTP/3 for Reaper:**
- ✅ **0-RTT reconnection** - Instant reconnect after first connection
- ✅ **Multiplexing** - No head-of-line blocking
- ✅ **Lower latency** - ~30% faster than HTTP/2 for AI APIs
- ✅ **Better mobile** - Handles network switches gracefully

**zhttp automatically prefers HTTP/3 when available:**

```zig
const client = try zhttp.Client.init(allocator, .{
    .protocol = .http3,    // Try HTTP/3 first
    .fallback = .http1,    // Fall back to HTTP/1.1 if unavailable
    .quic = .{
        .enable_0rtt = true,  // Enable 0-RTT for reconnections
        .max_idle_timeout = 300, // 5min idle timeout
    },
});
```

---

## 🔥 Performance Optimization

### 1. Connection Pooling

```zig
pub const ProviderPool = struct {
    allocator: std.mem.Allocator,
    openai: *OpenAIClient,
    claude: *ClaudeClient,
    copilot: *CopilotClient,
    ollama: ?*OllamaClient,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*ProviderPool {
        var self = try allocator.create(ProviderPool);
        self.allocator = allocator;

        // Initialize all providers with connection pooling
        self.openai = try OpenAIClient.init(allocator, config.openai_key);
        self.claude = try ClaudeClient.init(allocator, config.claude_key);
        self.copilot = try CopilotClient.init(allocator, config.copilot_token);

        if (config.ollama_url) |url| {
            self.ollama = try OllamaClient.init(allocator, url);
        } else {
            self.ollama = null;
        }

        return self;
    }

    pub fn selectBest(self: *ProviderPool, mode: enum { completion, agentic }) !*Provider {
        return switch (mode) {
            .completion => self.copilot, // Copilot is fastest
            .agentic => self.claude,     // Claude is smartest
        };
    }

    pub fn deinit(self: *ProviderPool) void {
        self.openai.deinit();
        self.claude.deinit();
        self.copilot.deinit();
        if (self.ollama) |ollama| ollama.deinit();
        self.allocator.destroy(self);
    }
};
```

### 2. Request Retry with Backoff

```zig
pub fn sendWithRetry(
    http: *zhttp.Client,
    request: zhttp.Request,
    max_attempts: u32,
) !zhttp.Response {
    var attempt: u32 = 0;
    var backoff_ms: u64 = 100;

    while (attempt < max_attempts) : (attempt += 1) {
        const response = http.send(request) catch |err| {
            if (attempt == max_attempts - 1) return err;

            std.log.warn("Request failed (attempt {d}/{d}): {s}", .{
                attempt + 1,
                max_attempts,
                @errorName(err),
            });

            std.time.sleep(backoff_ms * std.time.ns_per_ms);
            backoff_ms = @min(backoff_ms * 2, 5000);
            continue;
        };

        // Check for retryable status codes
        if (response.status_code == 429 or response.status_code >= 500) {
            response.deinit();

            if (attempt == max_attempts - 1) {
                return error.MaxRetriesExceeded;
            }

            std.time.sleep(backoff_ms * std.time.ns_per_ms);
            backoff_ms = @min(backoff_ms * 2, 5000);
            continue;
        }

        return response;
    }

    unreachable;
}
```

### 3. Response Caching

```zig
pub const ResponseCache = struct {
    cache: std.StringHashMap(CachedResponse),
    allocator: std.mem.Allocator,
    ttl_ms: u64,

    pub fn get(self: *ResponseCache, key: []const u8) ?[]const u8 {
        const entry = self.cache.get(key) orelse return null;

        if (std.time.milliTimestamp() - entry.timestamp > self.ttl_ms) {
            _ = self.cache.remove(key);
            return null;
        }

        return entry.response;
    }

    pub fn put(self: *ResponseCache, key: []const u8, response: []const u8) !void {
        try self.cache.put(
            try self.allocator.dupe(u8, key),
            .{
                .response = try self.allocator.dupe(u8, response),
                .timestamp = std.time.milliTimestamp(),
            },
        );
    }

    const CachedResponse = struct {
        response: []const u8,
        timestamp: i64,
    };
};
```

---

## 🛡️ Error Handling

### Graceful Degradation

```zig
pub fn completeWithFallback(
    pool: *ProviderPool,
    request: CompletionRequest,
) !?CompletionResponse {
    // Try Copilot first (fastest)
    if (pool.copilot.complete(request)) |response| {
        return response;
    } else |err| {
        std.log.warn("Copilot failed: {s}, trying Claude...", .{@errorName(err)});
    }

    // Fall back to Claude
    if (pool.claude.complete(request)) |response| {
        return response;
    } else |err| {
        std.log.warn("Claude failed: {s}, trying Ollama...", .{@errorName(err)});
    }

    // Fall back to local Ollama
    if (pool.ollama) |ollama| {
        if (ollama.complete(request)) |response| {
            return response;
        } else |err| {
            std.log.err("All providers failed, last error: {s}", .{@errorName(err)});
        }
    }

    return null; // All providers failed
}
```

---

## 📊 Monitoring

### Request Metrics

```zig
pub const HTTPMetrics = struct {
    requests_total: std.atomic.Value(u64),
    requests_failed: std.atomic.Value(u64),
    latency_total_ms: std.atomic.Value(u64),
    bytes_sent: std.atomic.Value(u64),
    bytes_received: std.atomic.Value(u64),

    pub fn recordRequest(
        self: *HTTPMetrics,
        latency_ms: u32,
        sent: usize,
        received: usize,
        err: ?anyerror,
    ) void {
        _ = self.requests_total.fetchAdd(1, .monotonic);
        _ = self.latency_total_ms.fetchAdd(latency_ms, .monotonic);
        _ = self.bytes_sent.fetchAdd(sent, .monotonic);
        _ = self.bytes_received.fetchAdd(received, .monotonic);

        if (err != null) {
            _ = self.requests_failed.fetchAdd(1, .monotonic);
        }
    }
};
```

---

## 🎯 Configuration

**`reaper.toml`** - HTTP client config:

```toml
[http]
# Protocol preference
protocol = "http3"      # http3, http2, http1
fallback = "http1"      # Fallback protocol

# Timeouts (milliseconds)
connect_timeout = 10000
read_timeout = 120000
write_timeout = 30000

# Retries
max_retries = 3
retry_backoff = 100    # Initial backoff (ms)

# Connection pool
[http.pool]
max_per_host = 10
max_total = 50
idle_timeout = 300     # seconds

# QUIC/HTTP3 settings
[http.quic]
enable_0rtt = true
max_idle_timeout = 300

# TLS
[http.tls]
verify_certificates = true
min_version = "tls_1_3"
```

---

## 📚 Next Steps

1. **Read REAPER_RPC.md** - gRPC communication via zrpc
2. **Read REAPER_INTEGRATION.md** - MCP integration via rune
3. **Check INTEGRATION_PLAN.md** - Full Ghost ecosystem integration

---

**Built with 💀 by Ghost Ecosystem**
*"You reap what you sow"* - Fast HTTP, fast AI.
