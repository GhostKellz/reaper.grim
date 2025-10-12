# Rune Integration with Reaper.grim

**Version:** 0.1.0
**Last Updated:** 2025-10-12
**Purpose:** Guide for integrating rune MCP client with reaper.grim and glyph

---

## 🎯 Overview

**Rune** is the **MCP (Model Context Protocol) client** that connects reaper.grim (Zig AI assistant) to **glyph** (Rust MCP server) for context gathering and tool calling.

```
┌─────────────────────────────────────────────┐
│  reaper.grim (Zig AI Assistant)             │
│  • Completion engine                        │
│  • Agentic engine                           │
│  • Provider management                      │
└────────────────┬────────────────────────────┘
                 │
                 │ via rune (MCP client)
                 ▼
┌─────────────────────────────────────────────┐
│  glyph (Rust MCP Server)                    │
│  https://github.com/ghostkellz/glyph        │
│  • LSP context (symbols, types)             │
│  • Git context (diffs, commits, blame)      │
│  • File operations (read, write, search)    │
│  • Tool execution (shell commands)          │
│  • Semantic search (codebase RAG)           │
└─────────────────────────────────────────────┘
```

**Why rune?**
- ⚡ **Blazing fast** - 3× faster than Rust MCP clients
- 🔌 **MCP protocol** - Full JSON-RPC 2.0 support
- 🎯 **Zero allocation** - Optimized for real-time use
- 🦎 **Pure Zig** - Native integration with reaper
- 🔄 **Async native** - Built on zsync for concurrency

---

## 📦 Installation

### Add to reaper.grim

```bash
cd /data/projects/reaper.grim

# Add rune dependency
zig fetch --save https://github.com/ghostkellz/rune/archive/refs/heads/main.tar.gz
```

### Update build.zig

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add rune dependency
    const rune = b.dependency("rune", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "reaper",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Import rune module
    exe.root_module.addImport("rune", rune.module("rune"));

    b.installArtifact(exe);
}
```

---

## 🔌 Integration with glyph

### 1. Start glyph MCP Server

```bash
# Clone glyph
git clone https://github.com/ghostkellz/glyph.git /data/projects/glyph
cd /data/projects/glyph

# Build
cargo build --release

# Start MCP server
./target/release/glyph serve \
  --transport ws \
  --port 7331 \
  --log-level info
```

**glyph provides these tools:**
- `lsp/symbols` - Get LSP symbols at cursor
- `lsp/hover` - Get hover documentation
- `lsp/diagnostics` - Get errors/warnings
- `git/status` - Git repository status
- `git/diff` - File diffs
- `git/blame` - Blame information
- `file/read` - Read file contents
- `file/write` - Write file contents
- `file/search` - Semantic search
- `tool/exec` - Execute shell commands

### 2. Connect from reaper.grim

```zig
// src/context/gatherer.zig
const std = @import("std");
const rune = @import("rune");
const zsync = @import("zsync");

pub const ContextGatherer = struct {
    allocator: std.mem.Allocator,
    mcp_client: *rune.Client,
    runtime: *zsync.Runtime,

    pub fn init(allocator: std.mem.Allocator) !ContextGatherer {
        // Connect to glyph MCP server
        const mcp_client = try rune.Client.connectWs(
            allocator,
            "ws://localhost:7331",
        );

        return ContextGatherer{
            .allocator = allocator,
            .mcp_client = mcp_client,
            .runtime = try zsync.Runtime.init(allocator),
        };
    }

    pub fn deinit(self: *ContextGatherer) void {
        self.mcp_client.deinit();
        self.runtime.deinit();
    }

    /// Gather LSP context for completion request
    pub fn gatherLspContext(
        self: *ContextGatherer,
        file_path: []const u8,
        cursor: struct { line: u32, col: u32 },
    ) !LspContext {
        // Call glyph's lsp/symbols tool
        const result = try self.mcp_client.invoke(.{
            .tool = "lsp/symbols",
            .input = .{
                .file = file_path,
                .position = .{
                    .line = cursor.line,
                    .character = cursor.col,
                },
            },
        });

        // Parse response
        const symbols = try std.json.parseFromSlice(
            []Symbol,
            self.allocator,
            result.string(),
            .{},
        );

        return LspContext{
            .symbols = symbols.value,
            .file = file_path,
            .cursor = cursor,
        };
    }

    /// Gather git context
    pub fn gatherGitContext(
        self: *ContextGatherer,
        file_path: []const u8,
    ) !GitContext {
        // Get git diff
        const diff_result = try self.mcp_client.invoke(.{
            .tool = "git/diff",
            .input = .{ .file = file_path },
        });

        // Get git blame
        const blame_result = try self.mcp_client.invoke(.{
            .tool = "git/blame",
            .input = .{ .file = file_path },
        });

        return GitContext{
            .diff = diff_result.string(),
            .blame = blame_result.string(),
        };
    }

    /// Execute tool for agentic tasks
    pub fn executeTool(
        self: *ContextGatherer,
        tool_name: []const u8,
        args: anytype,
    ) ![]const u8 {
        const result = try self.mcp_client.invoke(.{
            .tool = tool_name,
            .input = args,
        });

        return result.string();
    }
};
```

---

## 🚀 Usage Examples

### Example 1: Get LSP Context for Completion

```zig
// In completion engine
const gatherer = try ContextGatherer.init(allocator);
defer gatherer.deinit();

// Get LSP symbols at cursor
const lsp_ctx = try gatherer.gatherLspContext(
    "src/main.zig",
    .{ .line = 42, .col = 15 },
);

// Use symbols in completion prompt
for (lsp_ctx.symbols) |symbol| {
    std.debug.print("Symbol: {s} ({s})\n", .{
        symbol.name,
        symbol.kind,
    });
}
```

### Example 2: Get Git Context

```zig
// Get git diff for context
const git_ctx = try gatherer.gatherGitContext("src/parser.zig");

// Include diff in AI prompt
const prompt = try std.fmt.allocPrint(
    allocator,
    "Recent changes to this file:\n{s}\n\nNow complete: {s}",
    .{ git_ctx.diff, code_prefix },
);
```

### Example 3: Execute Tool (Agentic Task)

```zig
// Run tests via glyph
const test_result = try gatherer.executeTool("tool/exec", .{
    .cmd = "zig test src/parser.zig",
    .cwd = "/data/projects/reaper.grim",
});

std.debug.print("Test output:\n{s}\n", .{test_result});

// Parse test results
if (std.mem.indexOf(u8, test_result, "All tests passed")) |_| {
    std.debug.print("✓ Tests passed!\n", .{});
} else {
    std.debug.print("✗ Tests failed\n", .{});
}
```

### Example 4: Semantic Search (RAG)

```zig
// Search codebase for relevant context
const search_result = try gatherer.executeTool("file/search", .{
    .query = "authentication implementation",
    .path = "/data/projects/reaper.grim/src",
    .limit = 5,
});

// Parse search results
const files = try std.json.parseFromSlice(
    []struct {
        path: []const u8,
        score: f32,
        excerpt: []const u8,
    },
    allocator,
    search_result,
    .{},
);

// Include in context
for (files.value) |file| {
    std.debug.print("Found: {s} (score: {d:.2})\n", .{
        file.path,
        file.score,
    });
}
```

---

## 🔧 Configuration

### reaper.toml

```toml
[context]
# MCP server connection
mcp_enabled = true
mcp_url = "ws://localhost:7331"
mcp_timeout_ms = 5000

# Context gathering options
include_lsp = true
include_git = true
include_files = true
semantic_search = false  # Experimental

# Context budget (tokens)
max_tokens = 8000
lsp_budget = 1000
git_budget = 500
file_budget = 2000

[glyph]
# Auto-start glyph if not running
auto_start = true
binary_path = "/data/projects/glyph/target/release/glyph"
```

### Auto-start glyph

```zig
// src/context/glyph_manager.zig
pub fn ensureGlyphRunning(config: Config) !void {
    if (!config.glyph.auto_start) {
        return;
    }

    // Check if glyph is running
    const running = try isGlyphRunning(config.context.mcp_url);
    if (running) {
        return;
    }

    // Start glyph
    std.debug.print("Starting glyph MCP server...\n", .{});

    const argv = &[_][]const u8{
        config.glyph.binary_path,
        "serve",
        "--transport", "ws",
        "--port", "7331",
        "--log-level", "info",
    };

    var child = try std.ChildProcess.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    // Wait for glyph to be ready
    var retries: u8 = 0;
    while (retries < 10) : (retries += 1) {
        std.time.sleep(500 * std.time.ns_per_ms);

        if (try isGlyphRunning(config.context.mcp_url)) {
            std.debug.print("✓ Glyph started successfully\n", .{});
            return;
        }
    }

    return error.GlyphStartFailed;
}
```

---

## 🎯 Performance Optimization

### 1. Connection Pooling

```zig
pub const McpPool = struct {
    clients: []rune.Client,
    index: std.atomic.Atomic(usize),

    pub fn init(allocator: std.mem.Allocator, pool_size: usize) !McpPool {
        const clients = try allocator.alloc(rune.Client, pool_size);

        for (clients) |*client| {
            client.* = try rune.Client.connectWs(
                allocator,
                "ws://localhost:7331",
            );
        }

        return McpPool{
            .clients = clients,
            .index = std.atomic.Atomic(usize).init(0),
        };
    }

    pub fn getClient(self: *McpPool) *rune.Client {
        const idx = self.index.fetchAdd(1, .Monotonic) % self.clients.len;
        return &self.clients[idx];
    }
};
```

### 2. Caching

```zig
pub const ContextCache = struct {
    lru: std.AutoHashMap(u64, CachedContext),
    ttl_ms: u64,

    pub fn get(
        self: *ContextCache,
        key: []const u8,
    ) ?CachedContext {
        const hash = std.hash.Wyhash.hash(0, key);
        const cached = self.lru.get(hash) orelse return null;

        // Check TTL
        const now = std.time.milliTimestamp();
        if (now - cached.timestamp > self.ttl_ms) {
            _ = self.lru.remove(hash);
            return null;
        }

        return cached;
    }

    pub fn put(
        self: *ContextCache,
        key: []const u8,
        context: anytype,
    ) !void {
        const hash = std.hash.Wyhash.hash(0, key);
        try self.lru.put(hash, .{
            .context = context,
            .timestamp = std.time.milliTimestamp(),
        });
    }
};
```

---

## 🐛 Error Handling

### Connection Errors

```zig
pub fn connectWithRetry(
    allocator: std.mem.Allocator,
    url: []const u8,
    max_retries: u8,
) !*rune.Client {
    var retries: u8 = 0;

    while (retries < max_retries) : (retries += 1) {
        if (rune.Client.connectWs(allocator, url)) |client| {
            return client;
        } else |err| {
            std.log.warn("MCP connection failed (attempt {}/{}): {}", .{
                retries + 1,
                max_retries,
                err,
            });

            // Exponential backoff
            const delay_ms = @as(u64, 100) * (@as(u64, 1) << @intCast(retries));
            std.time.sleep(delay_ms * std.time.ns_per_ms);
        }
    }

    return error.McpConnectionFailed;
}
```

### Timeout Handling

```zig
pub fn invokeWithTimeout(
    client: *rune.Client,
    tool: []const u8,
    input: anytype,
    timeout_ms: u64,
) ![]const u8 {
    const result = try std.Thread.spawn(.{}, struct {
        fn call(c: *rune.Client, t: []const u8, i: anytype) ![]const u8 {
            const r = try c.invoke(.{ .tool = t, .input = i });
            return r.string();
        }
    }.call, .{ client, tool, input });

    // Wait with timeout
    const start = std.time.milliTimestamp();
    while (true) {
        if (result.poll()) |value| {
            return value;
        }

        const elapsed = std.time.milliTimestamp() - start;
        if (elapsed > timeout_ms) {
            result.cancel();
            return error.Timeout;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
    }
}
```

---

## 📊 Monitoring & Metrics

### Track MCP Performance

```zig
pub const McpMetrics = struct {
    total_calls: std.atomic.Atomic(u64),
    total_latency_ms: std.atomic.Atomic(u64),
    errors: std.atomic.Atomic(u64),

    pub fn recordCall(self: *McpMetrics, latency_ms: u64, err: ?anyerror) void {
        _ = self.total_calls.fetchAdd(1, .Monotonic);
        _ = self.total_latency_ms.fetchAdd(latency_ms, .Monotonic);

        if (err) |_| {
            _ = self.errors.fetchAdd(1, .Monotonic);
        }
    }

    pub fn getStats(self: *McpMetrics) struct {
        avg_latency_ms: f64,
        error_rate: f64,
    } {
        const calls = self.total_calls.load(.Monotonic);
        if (calls == 0) {
            return .{ .avg_latency_ms = 0, .error_rate = 0 };
        }

        const total_latency = self.total_latency_ms.load(.Monotonic);
        const errors = self.errors.load(.Monotonic);

        return .{
            .avg_latency_ms = @as(f64, @floatFromInt(total_latency)) / @as(f64, @floatFromInt(calls)),
            .error_rate = @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(calls)),
        };
    }
};
```

---

## 🔒 Security

### Consent Framework

```zig
// Require user consent for sensitive operations
const consent = try gatherer.mcp_client.requestConsent(.{
    .operation = "file.write",
    .resource = "/etc/hosts",
    .reason = "Modifying system hosts file",
});

if (!consent.granted) {
    return error.ConsentDenied;
}

// Proceed with operation
const result = try gatherer.executeTool("file/write", .{
    .path = "/etc/hosts",
    .content = new_content,
});
```

---

## 🧪 Testing

### Mock MCP Server for Tests

```zig
// tests/mock_mcp.zig
const MockMcpServer = struct {
    pub fn start(allocator: std.mem.Allocator) !*rune.Server {
        var server = try rune.Server.init(.{
            .transport = .{ .tcp = .{ .port = 7332 } },
        });

        // Register mock tools
        try server.registerTool("lsp/symbols", mockLspSymbols);
        try server.registerTool("git/diff", mockGitDiff);

        return server;
    }

    fn mockLspSymbols(ctx: *rune.ToolCtx, input: anytype) ![]const u8 {
        _ = input;
        return try std.json.stringifyAlloc(ctx.alloc, &[_]Symbol{
            .{ .name = "test_function", .kind = "function" },
        }, .{});
    }

    fn mockGitDiff(ctx: *rune.ToolCtx, input: anytype) ![]const u8 {
        _ = input;
        return "diff --git a/test.zig b/test.zig\n+new line\n";
    }
};

test "context gathering" {
    const server = try MockMcpServer.start(std.testing.allocator);
    defer server.deinit();

    const gatherer = try ContextGatherer.init(std.testing.allocator);
    defer gatherer.deinit();

    const ctx = try gatherer.gatherLspContext("test.zig", .{ .line = 1, .col = 1 });
    try std.testing.expect(ctx.symbols.len > 0);
}
```

---

## 📋 Checklist for Integration

### Phase 1: Basic Integration
- [ ] Add rune to build.zig.zon
- [ ] Update build.zig with rune module
- [ ] Create ContextGatherer struct
- [ ] Implement LSP context gathering
- [ ] Implement git context gathering
- [ ] Test with glyph running manually

### Phase 2: Auto-start
- [ ] Implement glyph auto-start
- [ ] Add health check
- [ ] Connection retry logic
- [ ] Configuration options

### Phase 3: Optimization
- [ ] Connection pooling
- [ ] Response caching
- [ ] Timeout handling
- [ ] Error handling

### Phase 4: Production
- [ ] Metrics & monitoring
- [ ] Security/consent framework
- [ ] Testing suite
- [ ] Documentation

---

## 🔗 Resources

- **Rune Repository:** https://github.com/ghostkellz/rune
- **Glyph Repository:** https://github.com/ghostkellz/glyph
- **MCP Specification:** https://spec.modelcontextprotocol.io/
- **Rune Benchmarks:** [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md)

---

**Last Updated:** 2025-10-12
**Status:** Production Ready (rune), Integration Guide
**Next:** Implement in reaper.grim Phase 4
