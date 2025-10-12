# Reaper.grim ⚡ zrpc Integration

**Using zrpc for High-Performance gRPC Communication in Reaper.grim**

---

## 🎯 Overview

**zrpc** is Reaper.grim's foundation for modern, high-performance RPC communication between:
- **Reaper daemon** (background AI service)
- **Grim editor** (client)
- **Plugin ecosystem** (extensions)

Unlike traditional HTTP-based AI tools, reaper uses **zrpc** for:
- ✅ **<10ms latency** - Critical for autocompletes (<100ms target)
- ✅ **Bidirectional streaming** - Real-time progress updates
- ✅ **QUIC transport** - Modern, multiplexed, 0-RTT connections
- ✅ **Type-safe APIs** - Compile-time checked service definitions
- ✅ **Pure Zig** - Native performance, no C dependencies

---

## 🏗️ Architecture

### Reaper RPC Design

```
┌─────────────────────────────────────────────────────────┐
│                    Grim Editor (Client)                  │
│  ┌────────────────────────────────────────────────────┐ │
│  │  - grim TUI                                  │ │
│  │  - Autocomplete UI                                 │ │
│  │  - Chat panel                                      │ │
│  │  - Progress indicators                             │ │
│  └──────────────┬─────────────────────────────────────┘ │
│                 │ zrpc.Client                            │
└─────────────────┼─────────────────────────────────────┬─┘
                  │                                      │
                  │ QUIC (127.0.0.1:50051)              │
                  │ - Multiplexed streams                │
                  │ - 0-RTT reconnect                    │
                  │ - TLS 1.3 (optional local auth)     │
                  │                                      │
┌─────────────────┼─────────────────────────────────────┘
│                 │ zrpc.Server
│  ┌──────────────▼──────────────────────────────────────┐
│  │  Reaper Daemon (Server)                            │
│  │                                                     │
│  │  Services:                                         │
│  │  ├── CompletionService   (autocomplete)           │
│  │  ├── ChatService         (conversations)          │
│  │  ├── AgentService        (multi-step tasks)       │
│  │  ├── ProviderService     (model management)       │
│  │  └── HealthService       (daemon status)          │
│  │                                                     │
│  │  Backend:                                          │
│  │  ├── AI Providers (Copilot, Claude, Ollama)       │
│  │  ├── MCP Client (rune → glyph for context)        │
│  │  ├── Cache Layer (completion/context caching)     │
│  │  └── zsync Runtime (async execution)              │
│  └─────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### 1. Installation

Add to `build.zig.zon`:
```zig
.dependencies = .{
    .zrpc = .{
        .url = "https://github.com/ghostkellz/zrpc/archive/refs/main.tar.gz",
        .hash = "...",
    },
},
```

### 2. Service Definition

**`src/rpc/services.zig`** - Reaper RPC service interfaces:

```zig
const std = @import("std");
const zrpc = @import("zrpc");

/// Fast autocomplete service (<100ms target)
pub const CompletionService = struct {
    pub const Request = struct {
        /// Buffer content before cursor
        prefix: []const u8,
        /// Buffer content after cursor
        suffix: []const u8,
        /// Programming language
        language: []const u8,
        /// File path (for context)
        file_path: ?[]const u8 = null,
        /// Additional context (LSP, git, etc.)
        context: ?ContextMetadata = null,

        pub const ContextMetadata = struct {
            lsp_symbols: ?[]const u8 = null,
            git_status: ?[]const u8 = null,
            project_files: ?[]const []const u8 = null,
        };
    };

    pub const Response = struct {
        /// Completion text to insert
        completion: []const u8,
        /// Completion confidence (0.0-1.0)
        confidence: f32,
        /// Provider used (copilot, claude, ollama)
        provider: []const u8,
        /// Latency in milliseconds
        latency_ms: u32,
    };

    pub const service_name = "reaper.Completion";
    pub const methods = .{
        .complete = .{
            .request = Request,
            .response = Response,
        },
    };
};

/// Conversational chat service
pub const ChatService = struct {
    pub const Message = struct {
        role: enum { user, assistant, system },
        content: []const u8,
        timestamp: i64,
    };

    pub const Request = struct {
        /// Conversation history
        messages: []const Message,
        /// Model preference
        model: ?[]const u8 = null,
        /// Max tokens to generate
        max_tokens: ?u32 = null,
    };

    pub const StreamChunk = struct {
        /// Partial response text
        delta: []const u8,
        /// True if this is the final chunk
        done: bool,
    };

    pub const service_name = "reaper.Chat";
    pub const methods = .{
        .send = .{
            .request = Request,
            .response_stream = StreamChunk,
        },
    };
};

/// Multi-step agentic task service
pub const AgentService = struct {
    pub const Task = struct {
        /// User instruction
        instruction: []const u8,
        /// Working directory
        cwd: []const u8,
        /// Max execution time (seconds)
        timeout: ?u32 = null,
    };

    pub const StepUpdate = struct {
        /// Current step number
        step: u32,
        /// Step description
        description: []const u8,
        /// Step status
        status: enum { planning, executing, verifying, completed, failed },
        /// Optional result/error
        message: ?[]const u8 = null,
    };

    pub const service_name = "reaper.Agent";
    pub const methods = .{
        .execute = .{
            .request = Task,
            .response_stream = StepUpdate,
        },
    };
};

/// Provider management service
pub const ProviderService = struct {
    pub const Provider = struct {
        name: []const u8,
        status: enum { available, unavailable, rate_limited },
        latency_ms: u32,
        auth_status: enum { authenticated, needs_auth, expired },
    };

    pub const ListResponse = struct {
        providers: []const Provider,
    };

    pub const service_name = "reaper.Provider";
    pub const methods = .{
        .list = .{
            .request = struct {},
            .response = ListResponse,
        },
    };
};
```

### 3. Server Implementation

**`src/daemon/server.zig`** - Reaper daemon RPC server:

```zig
const std = @import("std");
const zrpc = @import("zrpc");
const zsync = @import("zsync");
const services = @import("rpc/services.zig");

pub const ReaperServer = struct {
    allocator: std.mem.Allocator,
    server: *zrpc.Server,
    runtime: *zsync.Runtime,

    // Service handlers
    completion_handler: *CompletionHandler,
    chat_handler: *ChatHandler,
    agent_handler: *AgentHandler,
    provider_handler: *ProviderHandler,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*ReaperServer {
        var self = try allocator.create(ReaperServer);
        self.allocator = allocator;

        // Create zsync runtime for async operations
        self.runtime = try zsync.Runtime.init(allocator, .{
            .worker_threads = 4,
        });

        // Create zrpc server with QUIC transport
        self.server = try zrpc.Server.init(allocator, .{
            .transport = .{
                .quic = .{
                    .bind_address = config.bind_address,
                    .bind_port = config.bind_port,
                    // Optional: TLS for auth (even on localhost)
                    .tls = if (config.enable_tls) .{
                        .cert_path = config.tls_cert,
                        .key_path = config.tls_key,
                    } else null,
                },
            },
            .max_connections = 100,
            .idle_timeout = 300, // 5 minutes
        });

        // Initialize service handlers
        self.completion_handler = try CompletionHandler.init(allocator, self.runtime);
        self.chat_handler = try ChatHandler.init(allocator, self.runtime);
        self.agent_handler = try AgentHandler.init(allocator, self.runtime);
        self.provider_handler = try ProviderHandler.init(allocator);

        // Register services
        try self.registerServices();

        return self;
    }

    fn registerServices(self: *ReaperServer) !void {
        // Register CompletionService
        try self.server.registerUnary(
            services.CompletionService.service_name,
            "complete",
            services.CompletionService.Request,
            services.CompletionService.Response,
            self.completion_handler,
            CompletionHandler.handleComplete,
        );

        // Register ChatService (streaming response)
        try self.server.registerServerStreaming(
            services.ChatService.service_name,
            "send",
            services.ChatService.Request,
            services.ChatService.StreamChunk,
            self.chat_handler,
            ChatHandler.handleSend,
        );

        // Register AgentService (streaming response)
        try self.server.registerServerStreaming(
            services.AgentService.service_name,
            "execute",
            services.AgentService.Task,
            services.AgentService.StepUpdate,
            self.agent_handler,
            AgentHandler.handleExecute,
        );

        // Register ProviderService
        try self.server.registerUnary(
            services.ProviderService.service_name,
            "list",
            struct {},
            services.ProviderService.ListResponse,
            self.provider_handler,
            ProviderHandler.handleList,
        );
    }

    pub fn serve(self: *ReaperServer) !void {
        std.log.info("Reaper daemon listening on {s}:{d}", .{
            self.server.config.transport.quic.bind_address,
            self.server.config.transport.quic.bind_port,
        });

        try self.server.serve();
    }

    pub fn deinit(self: *ReaperServer) void {
        self.completion_handler.deinit();
        self.chat_handler.deinit();
        self.agent_handler.deinit();
        self.provider_handler.deinit();
        self.server.deinit();
        self.runtime.deinit();
        self.allocator.destroy(self);
    }
};

/// Completion service handler
const CompletionHandler = struct {
    allocator: std.mem.Allocator,
    runtime: *zsync.Runtime,
    provider_pool: *ProviderPool,
    cache: *CompletionCache,

    pub fn init(allocator: std.mem.Allocator, runtime: *zsync.Runtime) !*CompletionHandler {
        var self = try allocator.create(CompletionHandler);
        self.allocator = allocator;
        self.runtime = runtime;
        self.provider_pool = try ProviderPool.init(allocator);
        self.cache = try CompletionCache.init(allocator);
        return self;
    }

    pub fn handleComplete(
        self: *CompletionHandler,
        request: services.CompletionService.Request,
    ) !services.CompletionService.Response {
        const start = std.time.milliTimestamp();

        // Check cache first
        const cache_key = try self.cache.computeKey(request);
        if (self.cache.get(cache_key)) |cached| {
            return .{
                .completion = cached.completion,
                .confidence = cached.confidence,
                .provider = cached.provider,
                .latency_ms = @intCast(std.time.milliTimestamp() - start),
            };
        }

        // Select best provider (Copilot for speed, Claude for quality)
        const provider = try self.provider_pool.selectBest(.completion);

        // Request completion
        const result = try provider.complete(request);

        // Cache result
        try self.cache.put(cache_key, result);

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start));

        return .{
            .completion = result.text,
            .confidence = result.confidence,
            .provider = provider.name,
            .latency_ms = latency,
        };
    }

    pub fn deinit(self: *CompletionHandler) void {
        self.provider_pool.deinit();
        self.cache.deinit();
        self.allocator.destroy(self);
    }
};
```

### 4. Client Implementation

**`src/client/client.zig`** - Client for Grim editor:

```zig
const std = @import("std");
const zrpc = @import("zrpc");
const services = @import("rpc/services.zig");

pub const ReaperClient = struct {
    allocator: std.mem.Allocator,
    client: *zrpc.Client,
    connected: bool,

    pub fn init(allocator: std.mem.Allocator, daemon_address: []const u8) !*ReaperClient {
        var self = try allocator.create(ReaperClient);
        self.allocator = allocator;
        self.connected = false;

        // Create zrpc client with QUIC transport
        self.client = try zrpc.Client.init(allocator, .{
            .transport = .{
                .quic = .{
                    .server_address = daemon_address,
                    .server_port = 50051,
                },
            },
            .timeout = 5000, // 5s timeout
            .retry = .{
                .max_attempts = 3,
                .backoff_ms = 100,
            },
        });

        return self;
    }

    pub fn connect(self: *ReaperClient) !void {
        try self.client.connect();
        self.connected = true;
        std.log.info("Connected to Reaper daemon", .{});
    }

    /// Request autocomplete (unary RPC)
    pub fn complete(
        self: *ReaperClient,
        prefix: []const u8,
        suffix: []const u8,
        language: []const u8,
    ) !services.CompletionService.Response {
        if (!self.connected) return error.NotConnected;

        const request = services.CompletionService.Request{
            .prefix = prefix,
            .suffix = suffix,
            .language = language,
        };

        return try self.client.call(
            services.CompletionService.service_name,
            "complete",
            services.CompletionService.Request,
            services.CompletionService.Response,
            request,
        );
    }

    /// Send chat message (streaming RPC)
    pub fn chat(
        self: *ReaperClient,
        messages: []const services.ChatService.Message,
        callback: *const fn (services.ChatService.StreamChunk) void,
    ) !void {
        if (!self.connected) return error.NotConnected;

        const request = services.ChatService.Request{
            .messages = messages,
        };

        var stream = try self.client.callServerStreaming(
            services.ChatService.service_name,
            "send",
            services.ChatService.Request,
            services.ChatService.StreamChunk,
            request,
        );
        defer stream.close();

        while (try stream.next()) |chunk| {
            callback(chunk);
            if (chunk.done) break;
        }
    }

    /// Execute agentic task (streaming RPC)
    pub fn executeTask(
        self: *ReaperClient,
        instruction: []const u8,
        cwd: []const u8,
        callback: *const fn (services.AgentService.StepUpdate) void,
    ) !void {
        if (!self.connected) return error.NotConnected;

        const request = services.AgentService.Task{
            .instruction = instruction,
            .cwd = cwd,
        };

        var stream = try self.client.callServerStreaming(
            services.AgentService.service_name,
            "execute",
            services.AgentService.Task,
            services.AgentService.StepUpdate,
            request,
        );
        defer stream.close();

        while (try stream.next()) |update| {
            callback(update);
            if (update.status == .completed or update.status == .failed) break;
        }
    }

    /// List available AI providers
    pub fn listProviders(self: *ReaperClient) !services.ProviderService.ListResponse {
        if (!self.connected) return error.NotConnected;

        return try self.client.call(
            services.ProviderService.service_name,
            "list",
            struct {},
            services.ProviderService.ListResponse,
            .{},
        );
    }

    pub fn deinit(self: *ReaperClient) void {
        if (self.connected) {
            self.client.disconnect();
        }
        self.client.deinit();
        self.allocator.destroy(self);
    }
};
```

---

## 🎨 Grim Integration Example

**Using ReaperClient in phantom.grim:**

```zig
const std = @import("std");
const ReaperClient = @import("reaper_client").ReaperClient;
const phantom = @import("phantom");

pub const AutocompleteUI = struct {
    client: *ReaperClient,
    buffer: *phantom.Buffer,
    window: *phantom.Window,

    /// Show ghost text completion
    pub fn showCompletion(self: *AutocompleteUI) !void {
        const cursor = self.buffer.getCursor();
        const prefix = try self.buffer.getTextBefore(cursor);
        const suffix = try self.buffer.getTextAfter(cursor);
        const language = self.buffer.getLanguage();

        // Request completion from daemon
        const response = try self.client.complete(prefix, suffix, language);

        if (response.confidence < 0.5) {
            return; // Low confidence, don't show
        }

        // Render ghost text
        try self.window.renderGhostText(
            cursor,
            response.completion,
            .{ .style = .dim, .italic = true },
        );

        // Log performance
        if (response.latency_ms > 100) {
            std.log.warn("Completion latency: {d}ms (target <100ms)", .{response.latency_ms});
        }
    }

    /// Accept completion (Tab key)
    pub fn acceptCompletion(self: *AutocompleteUI) !void {
        const ghost_text = self.window.getGhostText() orelse return;
        try self.buffer.insert(ghost_text);
        self.window.clearGhostText();
    }
};

pub const ChatPanel = struct {
    client: *ReaperClient,
    panel: *phantom.Panel,
    messages: std.ArrayList([]const u8),

    /// Send message and stream response
    pub fn sendMessage(self: *ChatPanel, content: []const u8) !void {
        // Add user message to history
        try self.messages.append(content);
        try self.panel.appendLine(.{ .text = content, .style = .user });

        // Stream response from daemon
        var response_buffer = std.ArrayList(u8).init(self.panel.allocator);
        defer response_buffer.deinit();

        const messages = try self.buildMessageHistory();
        defer self.panel.allocator.free(messages);

        try self.client.chat(messages, struct {
            panel: *phantom.Panel,
            buffer: *std.ArrayList(u8),

            pub fn callback(chunk: services.ChatService.StreamChunk) void {
                // Append to buffer
                buffer.appendSlice(chunk.delta) catch return;

                // Update UI in real-time
                panel.updateLastLine(buffer.items) catch return;
                panel.render() catch return;
            }
        }{ .panel = self.panel, .buffer = &response_buffer }.callback);

        // Save assistant response
        try self.messages.append(try self.panel.allocator.dupe(u8, response_buffer.items));
    }
};
```

---

## ⚙️ Configuration

**`reaper.toml`** - Daemon configuration:

```toml
[daemon]
# Bind address for gRPC server
address = "127.0.0.1"
port = 50051

# Enable TLS (even for localhost, for auth/security)
enable_tls = false

# Logging
log_level = "info"
log_file = "/tmp/reaper.log"

[rpc]
# QUIC transport settings
max_connections = 100
idle_timeout = 300  # seconds
max_stream_data = 10485760  # 10MB

# Request timeouts
completion_timeout = 5000    # 5s
chat_timeout = 120000        # 2min
agent_timeout = 600000       # 10min

# Performance
worker_threads = 4
enable_compression = true

[cache]
# Completion caching
enabled = true
max_size = 10000  # entries
ttl = 3600        # 1 hour
```

---

## 🔥 Performance Optimization

### 1. Connection Pooling

```zig
pub const ClientPool = struct {
    clients: std.ArrayList(*ReaperClient),
    mutex: std.Thread.Mutex,
    max_size: usize,

    pub fn acquire(self: *ClientPool) !*ReaperClient {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.clients.items.len > 0) {
            return self.clients.pop();
        }

        // Create new client if pool empty
        return try ReaperClient.init(self.allocator, "127.0.0.1");
    }

    pub fn release(self: *ClientPool, client: *ReaperClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.clients.items.len < self.max_size) {
            self.clients.append(client) catch {
                client.deinit();
            };
        } else {
            client.deinit();
        }
    }
};
```

### 2. Request Batching

```zig
pub const BatchCompleter = struct {
    client: *ReaperClient,
    pending: std.ArrayList(CompletionRequest),
    timer: std.time.Timer,
    batch_size: usize = 10,
    batch_timeout_ms: u64 = 50,

    pub fn requestCompletion(self: *BatchCompleter, req: CompletionRequest) !void {
        try self.pending.append(req);

        // Flush if batch full or timeout reached
        if (self.pending.items.len >= self.batch_size or
            self.timer.read() >= self.batch_timeout_ms * std.time.ns_per_ms)
        {
            try self.flush();
        }
    }

    fn flush(self: *BatchCompleter) !void {
        if (self.pending.items.len == 0) return;

        // Send batched requests
        for (self.pending.items) |req| {
            _ = try self.client.complete(req.prefix, req.suffix, req.language);
        }

        self.pending.clearRetainingCapacity();
        self.timer.reset();
    }
};
```

### 3. Response Caching

```zig
pub const ResponseCache = struct {
    cache: std.HashMap(u64, CachedResponse, std.hash.Wyhash, std.hash_map.default_max_load_percentage),
    ttl_ms: u64,

    pub fn get(self: *ResponseCache, key: u64) ?CachedResponse {
        const entry = self.cache.get(key) orelse return null;

        // Check TTL
        if (std.time.milliTimestamp() - entry.timestamp > self.ttl_ms) {
            _ = self.cache.remove(key);
            return null;
        }

        return entry;
    }

    pub fn put(self: *ResponseCache, key: u64, response: CachedResponse) !void {
        try self.cache.put(key, .{
            .response = response.response,
            .timestamp = std.time.milliTimestamp(),
        });
    }
};
```

---

## 🛡️ Error Handling

### Reconnection Strategy

```zig
pub fn connectWithRetry(client: *ReaperClient, max_attempts: u32) !void {
    var attempt: u32 = 0;
    var backoff_ms: u64 = 100;

    while (attempt < max_attempts) : (attempt += 1) {
        client.connect() catch |err| {
            if (attempt == max_attempts - 1) {
                return err;
            }

            std.log.warn("Connection failed (attempt {d}/{d}): {s}", .{
                attempt + 1,
                max_attempts,
                @errorName(err),
            });

            std.time.sleep(backoff_ms * std.time.ns_per_ms);
            backoff_ms = @min(backoff_ms * 2, 5000); // Max 5s backoff
            continue;
        };

        return; // Success
    }
}
```

### Graceful Degradation

```zig
pub fn completeWithFallback(
    client: *ReaperClient,
    request: CompletionRequest,
) !?services.CompletionService.Response {
    return client.complete(
        request.prefix,
        request.suffix,
        request.language,
    ) catch |err| {
        std.log.err("Completion failed: {s}", .{@errorName(err)});

        // Fall back to local completion (if available)
        if (LocalCompleter.available()) {
            return try LocalCompleter.complete(request);
        }

        return null; // Graceful failure
    };
}
```

---

## 📊 Monitoring & Debugging

### Request Logging

```zig
const zlog = @import("zlog");

pub fn logRequest(
    service: []const u8,
    method: []const u8,
    latency_ms: u32,
    success: bool,
) void {
    zlog.info(.rpc, "RPC call", .{
        .service = service,
        .method = method,
        .latency_ms = latency_ms,
        .success = success,
    });
}
```

### Performance Metrics

```zig
pub const Metrics = struct {
    total_requests: std.atomic.Value(u64),
    total_errors: std.atomic.Value(u64),
    total_latency_ms: std.atomic.Value(u64),

    pub fn recordRequest(self: *Metrics, latency_ms: u32, err: ?anyerror) void {
        _ = self.total_requests.fetchAdd(1, .monotonic);
        _ = self.total_latency_ms.fetchAdd(latency_ms, .monotonic);

        if (err != null) {
            _ = self.total_errors.fetchAdd(1, .monotonic);
        }
    }

    pub fn getAverageLatency(self: *Metrics) f64 {
        const total = self.total_requests.load(.monotonic);
        if (total == 0) return 0.0;

        const latency = self.total_latency_ms.load(.monotonic);
        return @as(f64, @floatFromInt(latency)) / @as(f64, @floatFromInt(total));
    }

    pub fn getErrorRate(self: *Metrics) f64 {
        const total = self.total_requests.load(.monotonic);
        if (total == 0) return 0.0;

        const errors = self.total_errors.load(.monotonic);
        return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
    }
};
```

---

## 🎯 Why zrpc for Reaper?

| Feature | HTTP/REST | gRPC | **zrpc (Reaper)** |
|---------|-----------|------|-------------------|
| **Latency** | 50-200ms | 10-50ms | **<10ms** (QUIC) |
| **Streaming** | SSE (hack) | ✅ | ✅ Bidirectional |
| **Type Safety** | ❌ JSON | ✅ Protobuf | ✅ Zig types |
| **Binary Protocol** | ❌ | ✅ | ✅ |
| **0-RTT Reconnect** | ❌ | ❌ | ✅ (QUIC) |
| **Multiplexing** | HTTP/2 | HTTP/2 | **QUIC** |
| **Pure Zig** | ❌ | ❌ C | ✅ |

**zrpc gives Reaper the speed needed for real-time autocomplete (<100ms) while supporting long-running agentic tasks (minutes) via streaming.**

---

## 📚 Next Steps

1. **Read REAPER_HTTP.md** - HTTP client for AI provider APIs
2. **Read REAPER_INTEGRATION.md** - MCP integration via rune
3. **Check TODO.md** - Implementation roadmap

---

**Built with 💀 by Ghost Ecosystem**
*"You reap what you sow"* - Fast RPC, fast completions.
