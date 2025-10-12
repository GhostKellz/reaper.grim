# Reaper.grim - AI Assistant Specifications

**Version:** 0.1.0-alpha
**Last Updated:** 2025-10-12
**Status:** Design Phase

---

## 🎯 Vision

**Reaper.grim** is the **all-in-one AI coding assistant** built in **pure Zig** for the **Grim editor** and **phantom.grim** configuration framework.

> *"You reap what you sow"* - Better code, better context, better AI assistance.

### What is Reaper?

A **native Zig binary** that provides:
- 🤖 **Autocompletes** - GitHub Copilot-style inline suggestions
- 🧠 **Agentic Mode** - Claude Code-style multi-step tasks
- 💬 **Chat Interface** - Conversational AI for code help
- 🎯 **Prompts** - Pre-defined commands and workflows
- 🔐 **OAuth Integration** - Google Sign-In (Claude), GitHub Sign-In (Copilot)
- 🌐 **Multi-Provider** - OpenAI, Claude, Copilot, Ollama, custom endpoints

---

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────────────┐
│  Reaper.grim (Pure Zig Binary)                            │
│  All-in-One AI Assistant for Grim                         │
├───────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Completion Engine (zsync async)                    │ │
│  │  • Inline suggestions (<100ms)                      │ │
│  │  • Multi-line completions                           │ │
│  │  • Context-aware (LSP, git, files)                  │ │
│  │  • Streaming responses                              │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Agentic Engine (zsync async)                       │ │
│  │  • Multi-step task execution                        │ │
│  │  • Tool calling (files, LSP, git, shell)            │ │
│  │  • Plan-execute-verify loop                         │ │
│  │  • Progress streaming                               │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Provider Management                                 │ │
│  │  • GitHub Copilot (OAuth via zcrypto)               │ │
│  │  • Claude (Google Sign-In via zcrypto)              │ │
│  │  • OpenAI (API key)                                 │ │
│  │  • Ollama (local models)                            │ │
│  │  • Custom endpoints (self-hosted)                   │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Communication Layer                                 │ │
│  │  • gRPC (via zrpc) - Modern, fast                   │ │
│  │  • HTTP/3 (via zquic) - Fallback                    │ │
│  │  • MCP (via rune) - Context/tools                   │ │
│  │  • Streaming (Server-Sent Events)                   │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Context Engine (rune MCP integration)              │ │
│  │  • LSP context (symbols, types, diagnostics)        │ │
│  │  • Git context (diffs, commits, blame)              │ │
│  │  • File tree (project structure)                    │ │
│  │  • Semantic search (RAG over codebase)              │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Auth Management (zcrypto)                          │ │
│  │  • Google Sign-In (for Claude Code Max)             │ │
│  │  • GitHub OAuth (for Copilot)                       │ │
│  │  • API key storage (secure vault)                   │ │
│  │  • Token refresh                                    │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Infrastructure                                      │ │
│  │  • zlog (structured logging)                        │ │
│  │  • flare (configuration management)                 │ │
│  │  • flash (CLI framework)                            │ │
│  │  • phantom (TUI components)                         │ │
│  │  • zsync (async runtime)                            │ │
│  └─────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
                           │
                           │ (integration)
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌───────────────┐  ┌──────────────┐  ┌──────────────┐
│  Grim Editor  │  │ phantom.grim │  │  CLI Usage   │
│  (native)     │  │  (configs)   │  │  (terminal)  │
└───────────────┘  └──────────────┘  └──────────────┘
```

---

## 🔑 Key Differentiators

### vs zeke

| Feature | **reaper.grim** | **zeke** |
|---------|----------------|----------|
| Language | Pure Zig | Zig daemon + Ghostlang clients |
| Target | Grim-specific | Editor-agnostic |
| Auth | OAuth (Google, GitHub) | API keys only |
| Protocol | gRPC (zrpc) | zRPC (custom) |
| Deployment | Single binary | Daemon + plugins |
| Integration | Native Grim API | RPC-based |
| Speed | Ultra-fast (direct) | Fast (RPC overhead) |

**Philosophy:** reaper.grim is **Grim-native and batteries-included**.

---

## 📦 Ghost Ecosystem Integration

### Core Dependencies

```toml
# build.zig.zon
[dependencies]

# Async Runtime
zsync = "https://github.com/ghostkellz/zsync"

# RPC Framework (gRPC-like)
zrpc = "https://github.com/ghostkellz/zrpc"

# Logging
zlog = "https://github.com/ghostkellz/zlog"

# Crypto (OAuth, API keys)
zcrypto = "https://github.com/ghostkellz/zcrypto"

# HTTP/QUIC Client
zquic = "https://github.com/ghostkellz/zquic"
zhttp = "https://github.com/ghostkellz/zhttp"

# MCP Integration
rune = "https://github.com/ghostkellz/rune"

# Configuration
flare = "https://github.com/ghostkellz/flare"

# CLI Framework
flash = "https://github.com/ghostkellz/flash"

# TUI Components
phantom = "https://github.com/ghostkellz/phantom"

# Serialization
zcrate = "https://github.com/ghostkellz/zcrate"
```

### Optional Dependencies

```toml
# Compression (for large responses)
zpack = "https://github.com/ghostkellz/zpack"

# Regex (for pattern matching)
zregex = "https://github.com/ghostkellz/zregex"

# Time (for timestamps, rate limiting)
ztime = "https://github.com/ghostkellz/ztime"

# Testing
ghostspec = "https://github.com/ghostkellz/ghostspec"
```

---

## 🔐 Authentication

### 1. Google Sign-In (for Claude Code Max)

**Flow:**
```
User: reaper auth google
  ↓
1. Start OAuth flow via zcrypto
2. Open browser to Google OAuth page
3. User signs in with Google account
4. Google redirects with auth code
5. Exchange for access token
6. Store securely in vault
7. Use for Claude API requests
```

**Implementation:**
```zig
// src/auth/google.zig
const zcrypto = @import("zcrypto");
const flare = @import("flare");

pub const GoogleAuth = struct {
    client_id: []const u8,
    client_secret: []const u8,
    oauth_client: *zcrypto.OAuth2Client,

    pub fn init(allocator: std.mem.Allocator) !GoogleAuth {
        const config = try flare.get("auth.google");

        return GoogleAuth{
            .client_id = config.client_id,
            .client_secret = config.client_secret,
            .oauth_client = try zcrypto.OAuth2Client.init(allocator, .{
                .provider = .google,
                .client_id = config.client_id,
                .client_secret = config.client_secret,
                .redirect_uri = "http://localhost:8080/callback",
                .scopes = &.{"openid", "profile", "email"},
            }),
        };
    }

    pub fn startAuthFlow(self: *GoogleAuth) !void {
        // Generate auth URL
        const auth_url = try self.oauth_client.getAuthUrl();

        // Open browser
        try openBrowser(auth_url);

        // Start local callback server
        try self.oauth_client.waitForCallback();

        // Exchange code for token
        const token = try self.oauth_client.getAccessToken();

        // Store securely
        try vault.store("google_access_token", token.access_token);
        try vault.store("google_refresh_token", token.refresh_token);

        std.log.info("✓ Signed in with Google", .{});
    }

    pub fn getAccessToken(self: *GoogleAuth) ![]const u8 {
        // Get from vault
        if (vault.get("google_access_token")) |token| {
            // Check if expired
            if (!isTokenExpired(token)) {
                return token;
            }
        }

        // Refresh token
        const refresh_token = try vault.get("google_refresh_token");
        const new_token = try self.oauth_client.refreshToken(refresh_token);

        try vault.store("google_access_token", new_token.access_token);
        return new_token.access_token;
    }
};
```

### 2. GitHub Sign-In (for Copilot)

**Flow:**
```
User: reaper auth github
  ↓
1. Device flow (no redirect needed)
2. Display code: "ABC-1234"
3. User visits github.com/login/device
4. Enters code
5. Poll GitHub until authorized
6. Receive access token
7. Store securely
8. Use for Copilot API
```

**Implementation:**
```zig
// src/auth/github.zig
pub const GitHubAuth = struct {
    // Similar to GoogleAuth but using device flow
    pub fn startDeviceFlow(self: *GitHubAuth) !void {
        // Request device code
        const device_code_response = try self.requestDeviceCode();

        // Display to user
        std.log.info("Visit: {s}", .{device_code_response.verification_uri});
        std.log.info("Enter code: {s}", .{device_code_response.user_code});

        // Poll for authorization
        while (true) {
            std.time.sleep(device_code_response.interval * std.time.ns_per_s);

            if (try self.pollForToken(device_code_response.device_code)) |token| {
                try vault.store("github_access_token", token);
                std.log.info("✓ Signed in with GitHub", .{});
                return;
            }
        }
    }
};
```

### 3. API Key Management

**For OpenAI, custom endpoints:**

```zig
// src/auth/api_key.zig
pub fn setApiKey(provider: []const u8, key: []const u8) !void {
    const vault_key = try std.fmt.allocPrint(
        allocator,
        "{s}_api_key",
        .{provider},
    );
    defer allocator.free(vault_key);

    try vault.store(vault_key, key);
}

pub fn getApiKey(provider: []const u8) ![]const u8 {
    const vault_key = try std.fmt.allocPrint(
        allocator,
        "{s}_api_key",
        .{provider},
    );
    defer allocator.free(vault_key);

    return try vault.get(vault_key);
}
```

---

## 🚀 Communication Layer

### gRPC via zrpc

**Why gRPC over HTTP:**
- ✅ Faster (binary protocol, multiplexing)
- ✅ Streaming (bi-directional)
- ✅ Type-safe (protobuf-like)
- ✅ Modern (HTTP/2)

**Service Definition:**
```zig
// src/rpc/service.zig
const zrpc = @import("zrpc");

pub const ReaperService = zrpc.Service(&.{
    .name = "Reaper",
    .version = "v1",
    .methods = &.{
        // Completion methods
        zrpc.Method{
            .name = "Complete",
            .input = CompletionRequest,
            .output = CompletionResponse,
            .streaming = .server,  // Server streams responses
        },

        // Agentic methods
        zrpc.Method{
            .name = "ExecuteTask",
            .input = TaskRequest,
            .output = TaskResponse,
            .streaming = .bidirectional,  // Both stream
        },

        // Chat methods
        zrpc.Method{
            .name = "Chat",
            .input = ChatMessage,
            .output = ChatResponse,
            .streaming = .bidirectional,
        },
    },
});
```

**Server:**
```zig
// src/rpc/server.zig
pub const Server = struct {
    service: *ReaperService,
    listener: *zrpc.Listener,

    pub fn init(allocator: std.mem.Allocator) !Server {
        const service = try allocator.create(ReaperService);
        service.* = try ReaperService.init(allocator);

        const listener = try zrpc.Listener.init(allocator, .{
            .address = "127.0.0.1:50051",
            .tls = null,  // TLS optional for local
        });

        return Server{
            .service = service,
            .listener = listener,
        };
    }

    pub fn start(self: *Server) !void {
        try self.listener.serve(self.service);
    }
};
```

**Client (from Grim):**
```zig
// Grim editor calls reaper via gRPC
const client = try zrpc.Client.connect("127.0.0.1:50051");

// Stream completion
var stream = try client.call(
    ReaperService.Complete,
    CompletionRequest{
        .buffer = buffer_content,
        .cursor = cursor_pos,
        .language = "zig",
    },
);

while (try stream.recv()) |response| {
    // Update inline suggestion
    updateGhostText(response.text);
}
```

---

## 🧠 Provider Integration

### 1. GitHub Copilot

**Endpoint:**
```
POST https://copilot-proxy.githubusercontent.com/v1/completions
Authorization: Bearer <github_token>
```

**Implementation:**
```zig
// src/providers/copilot.zig
const zhttp = @import("zhttp");

pub const CopilotProvider = struct {
    auth: *GitHubAuth,
    http_client: *zhttp.Client,

    pub fn complete(
        self: *CopilotProvider,
        ctx: Context,
    ) !CompletionResponse {
        const token = try self.auth.getAccessToken();

        const request = .{
            .method = .POST,
            .url = "https://copilot-proxy.githubusercontent.com/v1/completions",
            .headers = &.{
                .{ "Authorization", try std.fmt.allocPrint(
                    allocator,
                    "Bearer {s}",
                    .{token},
                ) },
                .{ "Content-Type", "application/json" },
            },
            .body = try std.json.stringifyAlloc(allocator, .{
                .prompt = ctx.prompt,
                .suffix = ctx.suffix,
                .max_tokens = 500,
                .temperature = 0.2,
            }, .{}),
        };

        const response = try self.http_client.request(request);
        defer response.deinit();

        const parsed = try std.json.parseFromSlice(
            CopilotResponse,
            allocator,
            response.body,
            .{},
        );

        return CompletionResponse{
            .text = parsed.choices[0].text,
            .provider = "copilot",
            .cached = false,
        };
    }
};
```

### 2. Claude (via Google Sign-In)

**Endpoint:**
```
POST https://api.anthropic.com/v1/messages
Authorization: Bearer <google_access_token>
```

**Implementation:**
```zig
// src/providers/claude.zig
pub const ClaudeProvider = struct {
    auth: *GoogleAuth,
    http_client: *zhttp.Client,

    pub fn complete(
        self: *ClaudeProvider,
        ctx: Context,
    ) !CompletionResponse {
        const token = try self.auth.getAccessToken();

        const request = .{
            .method = .POST,
            .url = "https://api.anthropic.com/v1/messages",
            .headers = &.{
                .{ "Authorization", try std.fmt.allocPrint(
                    allocator,
                    "Bearer {s}",
                    .{token},
                ) },
                .{ "anthropic-version", "2023-06-01" },
                .{ "Content-Type", "application/json" },
            },
            .body = try std.json.stringifyAlloc(allocator, .{
                .model = "claude-sonnet-4-5-20250929",
                .messages = &.{
                    .{
                        .role = "user",
                        .content = ctx.prompt,
                    },
                },
                .max_tokens = 1024,
                .stream = true,
            }, .{}),
        };

        // Stream response
        const stream = try self.http_client.stream(request);
        defer stream.close();

        var completion = std.ArrayList(u8).init(allocator);
        defer completion.deinit();

        while (try stream.readLine()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                const data = line[6..];
                const parsed = try std.json.parseFromSlice(
                    StreamEvent,
                    allocator,
                    data,
                    .{},
                );

                if (parsed.delta.text) |text| {
                    try completion.appendSlice(text);
                    // Yield to stream to client
                    try ctx.yield(text);
                }
            }
        }

        return CompletionResponse{
            .text = try completion.toOwnedSlice(),
            .provider = "claude",
            .cached = false,
        };
    }
};
```

### 3. Ollama (Local Models)

**Endpoint:**
```
POST http://localhost:11434/api/generate
```

**Implementation:**
```zig
// src/providers/ollama.zig
pub const OllamaProvider = struct {
    url: []const u8,
    model: []const u8,
    http_client: *zhttp.Client,

    pub fn complete(
        self: *OllamaProvider,
        ctx: Context,
    ) !CompletionResponse {
        const request = .{
            .method = .POST,
            .url = try std.fmt.allocPrint(
                allocator,
                "{s}/api/generate",
                .{self.url},
            ),
            .headers = &.{
                .{ "Content-Type", "application/json" },
            },
            .body = try std.json.stringifyAlloc(allocator, .{
                .model = self.model,
                .prompt = ctx.prompt,
                .stream = false,
            }, .{}),
        };

        const response = try self.http_client.request(request);
        defer response.deinit();

        const parsed = try std.json.parseFromSlice(
            OllamaResponse,
            allocator,
            response.body,
            .{},
        );

        return CompletionResponse{
            .text = parsed.response,
            .provider = "ollama",
            .cached = false,
        };
    }
};
```

---

## ⚙️ Configuration

### reaper.toml

```toml
[daemon]
address = "127.0.0.1:50051"
log_level = "info"
log_file = "~/.local/share/reaper/reaper.log"

[modes]
completion = true
agent = true
chat = true

[completion]
latency_target_ms = 100
max_tokens = 500
temperature = 0.2
debounce_ms = 300

[agent]
max_task_time_minutes = 60
tool_calling = true
auto_verify = true

[chat]
max_history = 50
persist_conversations = true

[providers]
# Copilot (via GitHub OAuth)
[providers.copilot]
enabled = true
auth = "github_oauth"
priority = 1

# Claude (via Google Sign-In)
[providers.claude]
enabled = true
auth = "google_oauth"
model = "claude-sonnet-4-5"
priority = 2

# OpenAI (API key)
[providers.openai]
enabled = true
auth = "api_key"
api_key_cmd = "pass openai-key"
models = ["gpt-4", "gpt-3.5-turbo"]
priority = 3

# Ollama (local)
[providers.ollama]
enabled = true
url = "http://localhost:11434"
models = ["codellama:13b", "deepseek-coder:6.7b"]
priority = 4

[selection]
strategy = "auto"  # auto, manual, cheapest, fastest
fallback = true
prefer_local = true

[context]
max_tokens = 8000
include_lsp = true
include_git = true
include_files = true
semantic_search = false

[auth]
vault_backend = "system"  # system, file, encrypted_file

[security]
strip_secrets = true
cache_locally = true
telemetry = false
```

---

## 🎮 CLI Interface

**Commands:**

```bash
# Auth
reaper auth google       # Sign in with Google (Claude)
reaper auth github       # Sign in with GitHub (Copilot)
reaper auth set-key <provider> <key>  # Set API key
reaper auth status       # Show auth status

# Server
reaper start             # Start daemon
reaper stop              # Stop daemon
reaper restart           # Restart daemon
reaper status            # Check status

# Test
reaper complete "fn main() {"  # Test completion
reaper ask "How do I..."       # Test question
reaper execute "Add tests"     # Test agentic task

# Config
reaper config get <key>        # Get config value
reaper config set <key> <val>  # Set config value
reaper config list             # List all config

# Logs
reaper logs                    # Tail logs
reaper logs -f                 # Follow logs
```

---

## 📊 Performance Targets

| Metric | Target | Stretch |
|--------|--------|---------|
| Completion latency | <100ms | <50ms |
| gRPC round-trip | <5ms | <2ms |
| Memory usage | <100MB | <50MB |
| Startup time | <1s | <500ms |
| Auth flow | <30s | <15s |

---

## 🛣️ Development Phases

### Phase 1: Foundation (Weeks 1-2)
- [ ] Project skeleton with Ghost dependencies
- [ ] gRPC server via zrpc
- [ ] Basic configuration via flare
- [ ] Logging via zlog
- [ ] CLI framework via flash

### Phase 2: Authentication (Weeks 3-4)
- [ ] Google OAuth implementation
- [ ] GitHub OAuth (device flow)
- [ ] API key management
- [ ] Secure vault storage

### Phase 3: Providers (Weeks 5-6)
- [ ] Ollama provider (simplest)
- [ ] OpenAI provider
- [ ] Claude provider
- [ ] GitHub Copilot provider
- [ ] Provider selection logic

### Phase 4: Completion Engine (Weeks 7-8)
- [ ] Context gathering (LSP, git, files)
- [ ] Completion request handler
- [ ] Response streaming
- [ ] Caching layer

### Phase 5: Agentic Engine (Weeks 9-10)
- [ ] Task planner
- [ ] Tool calling framework
- [ ] Step executor
- [ ] Result verifier

### Phase 6: Integration (Weeks 11-12)
- [ ] Grim editor integration
- [ ] phantom.grim plugin
- [ ] TUI components via phantom
- [ ] Testing & polish

---

**Last Updated:** 2025-10-12
**Status:** Design Phase
**Team:** Ghost Ecosystem
**Related:** grim, phantom.grim, zeke
