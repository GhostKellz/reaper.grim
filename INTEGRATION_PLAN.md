# Reaper.grim Integration Plan

**Version:** 0.1.0-alpha
**Last Updated:** 2025-10-12
**Purpose:** Detailed plan for integrating Ghost Ecosystem projects

---

## 🎯 Overview

Reaper.grim leverages **20+ Ghost Ecosystem projects** to provide a comprehensive AI development tool. This document details:
- Which projects to use
- How to add them (zig fetch --save)
- Integration strategy
- Dependencies between projects

---

## 📦 Core Zig Dependencies

### Tier 1: Essential (Must Have)

#### 1. zsync - Async Runtime ⭐
**Purpose:** High-performance async/await for all I/O operations
**Status:** RC (Release Candidate)
**Why:** Foundation for all network requests, file I/O, concurrent tasks

```bash
zig fetch --save https://github.com/ghostkellz/zsync/archive/refs/main.tar.gz
```

**Usage:**
```zig
const zsync = @import("zsync");

pub fn main() !void {
    var runtime = try zsync.Runtime.init();
    defer runtime.deinit();

    try runtime.spawn(asyncTask());
    try runtime.run();
}
```

**Integration Points:**
- HTTP client requests (all providers)
- gRPC server handling
- File operations
- Background tasks

---

#### 2. zrpc - gRPC Framework ⭐
**Purpose:** Modern RPC communication between reaper daemon and clients
**Status:** Stable
**Why:** Fast, streaming, type-safe communication

```bash
zig fetch --save https://github.com/ghostkellz/zrpc/archive/refs/main.tar.gz
```

**Usage:**
```zig
const zrpc = @import("zrpc");

// Define service
pub const ReaperService = zrpc.Service(&.{
    .name = "Reaper",
    .methods = &.{
        zrpc.Method{
            .name = "Complete",
            .input = CompletionRequest,
            .output = CompletionResponse,
            .streaming = .server,
        },
    },
});

// Start server
const server = try zrpc.Server.init("127.0.0.1:50051");
try server.serve(ReaperService);
```

**Integration Points:**
- Daemon RPC server
- Client-server communication
- Streaming completions
- Bidirectional chat

---

#### 3. zlog - Structured Logging ⭐
**Purpose:** High-performance logging with multiple backends
**Status:** Stable
**Why:** Essential for debugging, monitoring, telemetry

```bash
zig fetch --save https://github.com/ghostkellz/zlog/archive/refs/main.tar.gz
```

**Usage:**
```zig
const zlog = @import("zlog");

// Initialize logger
var logger = try zlog.Logger.init(allocator, .{
    .level = .info,
    .output = .{ .file = "reaper.log" },
    .format = .json,
});

// Log structured data
try logger.info("Completion requested", .{
    .provider = "ollama",
    .latency_ms = 87,
    .cached = false,
});
```

**Integration Points:**
- All modules (universal logging)
- Performance metrics
- Error tracking
- Audit trail

---

#### 4. zcrypto - Cryptography & OAuth ⭐
**Purpose:** OAuth flows, token encryption, secure storage
**Status:** Stable
**Why:** Essential for Google/GitHub OAuth

```bash
zig fetch --save https://github.com/ghostkellz/zcrypto/archive/refs/main.tar.gz
```

**Usage:**
```zig
const zcrypto = @import("zcrypto");

// OAuth client
const oauth = try zcrypto.OAuth2Client.init(allocator, .{
    .provider = .google,
    .client_id = "...",
    .client_secret = "...",
    .redirect_uri = "http://localhost:8080/callback",
});

const token = try oauth.getAccessToken();

// Encryption
const encrypted = try zcrypto.aes256.encrypt(plaintext, key);
```

**Integration Points:**
- Google OAuth (Claude)
- GitHub OAuth (Copilot)
- Token storage (encrypted vault)
- Secure configuration

---

#### 5. zhttp - HTTP Client ⭐
**Purpose:** HTTP/1.1 and HTTP/2 client for API requests
**Status:** Alpha/MVP
**Why:** Needed for REST APIs (OpenAI, Claude, Copilot)

```bash
zig fetch --save https://github.com/ghostkellz/zhttp/archive/refs/main.tar.gz
```

**Usage:**
```zig
const zhttp = @import("zhttp");

const client = try zhttp.Client.init(allocator);
defer client.deinit();

const response = try client.request(.{
    .method = .POST,
    .url = "https://api.openai.com/v1/completions",
    .headers = &.{
        .{ "Authorization", "Bearer sk-..." },
        .{ "Content-Type", "application/json" },
    },
    .body = json_body,
});
```

**Integration Points:**
- OpenAI API
- Anthropic (Claude) API
- GitHub Copilot API
- Custom endpoints

---

#### 6. rune - MCP Integration ⭐
**Purpose:** Model Context Protocol for context gathering
**Status:** Next-gen MCP library
**Why:** Integration with glyph (Rust MCP server) for LSP/git context

```bash
zig fetch --save https://github.com/ghostkellz/rune/archive/refs/main.tar.gz
```

**Usage:**
```zig
const rune = @import("rune");

// Connect to MCP server (glyph)
const mcp_client = try rune.Client.connect("http://localhost:3000");

// Request LSP context
const symbols = try mcp_client.call("lsp/symbols", .{
    .file = "src/main.zig",
    .position = cursor_pos,
});

// Request git context
const git_status = try mcp_client.call("git/status", .{
    .repo = project_root,
});
```

**Integration Points:**
- Context gathering (LSP symbols, types, diagnostics)
- Git integration (diffs, commits, blame)
- File operations
- Tool calling

---

#### 7. flare - Configuration Management ⭐
**Purpose:** Hierarchical config loading with type safety
**Status:** Stable
**Why:** Load reaper.toml, env vars, CLI flags

```bash
zig fetch --save https://github.com/ghostkellz/flare/archive/refs/main.tar.gz
```

**Usage:**
```zig
const flare = @import("flare");

const Config = struct {
    daemon: struct {
        address: []const u8,
        log_level: enum { debug, info, warn, err },
    },
    providers: struct {
        ollama: struct {
            enabled: bool,
            url: []const u8,
        },
    },
};

// Load config
const config = try flare.load(Config, .{
    .files = &.{"reaper.toml", "~/.config/reaper/reaper.toml"},
    .env_prefix = "REAPER_",
});

// Access
std.debug.print("Address: {s}\n", .{config.daemon.address});
```

**Integration Points:**
- Global configuration
- Provider settings
- Feature flags
- User preferences

---

#### 8. flash - CLI Framework ⭐
**Purpose:** Modern CLI with subcommands, flags, help
**Status:** Stable
**Why:** `reaper auth google`, `reaper start`, etc.

```bash
zig fetch --save https://github.com/ghostkellz/flash/archive/refs/main.tar.gz
```

**Usage:**
```zig
const flash = @import("flash");

const cli = flash.CLI(&.{
    .name = "reaper",
    .version = "0.1.0",
    .description = "AI coding assistant for Grim",
    .commands = &.{
        flash.Command{
            .name = "auth",
            .description = "Authenticate with providers",
            .subcommands = &.{
                flash.Command{
                    .name = "google",
                    .run = authGoogle,
                },
                flash.Command{
                    .name = "github",
                    .run = authGitHub,
                },
            },
        },
        flash.Command{
            .name = "start",
            .description = "Start daemon",
            .run = startDaemon,
        },
    },
});

try cli.run();
```

**Integration Points:**
- Main entry point
- All CLI commands
- Help text generation
- Arg parsing

---

### Tier 2: Important (Highly Recommended)

#### 9. phantom - TUI Framework
**Purpose:** Terminal UI components (chat panel, progress, etc.)
**Status:** Async-native TUI
**Why:** Beautiful UI in terminal

```bash
zig fetch --save https://github.com/ghostkellz/phantom/archive/refs/main.tar.gz
```

**Usage:**
```zig
const phantom = @import("phantom");

const chat_panel = try phantom.Panel.init(allocator, .{
    .position = .right,
    .width = 50,
    .title = "Reaper AI",
});

try chat_panel.addMessage("You", "How do I...");
try chat_panel.addMessage("Reaper", "Here's how...");
try chat_panel.render();
```

**Integration Points:**
- Chat interface
- Progress indicators
- Status displays
- Diff previews

---

#### 10. zcrate - Serialization
**Purpose:** Efficient serialization (protobuf/msgpack alternative)
**Status:** Stable
**Why:** Fast data serialization for RPC

```bash
zig fetch --save https://github.com/ghostkellz/zcrate/archive/refs/main.tar.gz
```

**Usage:**
```zig
const zcrate = @import("zcrate");

const CompletionRequest = struct {
    buffer: []const u8,
    cursor: Cursor,
    language: []const u8,
};

// Serialize
const bytes = try zcrate.serialize(allocator, request);

// Deserialize
const request = try zcrate.deserialize(CompletionRequest, bytes);
```

**Integration Points:**
- RPC message serialization
- Cache storage
- Network protocol

---

#### 11. zpack - Compression
**Purpose:** Fast compression for large responses
**Status:** RC
**Why:** Compress cached completions, reduce network traffic

```bash
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/main.tar.gz
```

**Usage:**
```zig
const zpack = @import("zpack");

const compressed = try zpack.compress(data, .zstd);
const decompressed = try zpack.decompress(compressed, .zstd);
```

**Integration Points:**
- Response caching
- Network optimization
- Storage efficiency

---

#### 12. ztime - Date/Time Library
**Purpose:** Time handling, durations, timestamps
**Status:** Alpha
**Why:** Rate limiting, cache TTL, timestamps

```bash
zig fetch --save https://github.com/ghostkellz/ztime/archive/refs/main.tar.gz
```

**Usage:**
```zig
const ztime = @import("ztime");

const now = try ztime.now();
const expiry = now.add(.{ .minutes = 5 });

if (now.isAfter(expiry)) {
    // Cache expired
}
```

**Integration Points:**
- Cache TTL
- Rate limiting
- Performance metrics
- Logging timestamps

---

#### 13. zregex - Regular Expressions
**Purpose:** Fast regex matching
**Status:** Stable
**Why:** Pattern matching, validation

```bash
zig fetch --save https://github.com/ghostkellz/zregex/archive/refs/main.tar.gz
```

**Integration Points:**
- Context extraction
- Code analysis
- Pattern matching

---

### Tier 3: Optional (Nice to Have)

#### 14. zquic - QUIC/HTTP3 Client
**Purpose:** HTTP/3 support (faster than HTTP/2)
**Status:** High-performance QUIC
**Why:** Faster cloud API requests

```bash
zig fetch --save https://github.com/ghostkellz/zquic/archive/refs/main.tar.gz
```

**Integration Points:**
- Fallback from zhttp
- Cloud provider APIs
- Future-proofing

---

#### 15. ghostspec - Testing Framework
**Purpose:** Property-based testing, fuzzing, benchmarking
**Status:** Comprehensive testing
**Why:** Test all components

```bash
zig fetch --save https://github.com/ghostkellz/ghostspec/archive/refs/main.tar.gz
```

**Integration Points:**
- Unit tests
- Integration tests
- Benchmarks
- Fuzzing

---

#### 16. zdoc - Documentation Generator
**Purpose:** Generate docs from code
**Status:** Alpha
**Why:** Auto-generate API docs

```bash
zig fetch --save https://github.com/ghostkellz/zdoc/archive/refs/main.tar.gz
```

---

## 🦀 Rust Integration (Optional)

### glyph - MCP Server (Rust)
**Purpose:** Rust-based MCP server for context/tools
**Status:** Production-ready
**Why:** Advanced context gathering, tool calling

**Integration:**
```bash
# In separate glyph project
git clone https://github.com/ghostkellz/glyph.git
cd glyph
cargo build --release

# Start glyph MCP server
./target/release/glyph serve --port 3000
```

**Reaper connects via rune:**
```zig
const mcp = try rune.Client.connect("http://localhost:3000");
```

---

### omen - AI Provider Adapters (Rust)
**Purpose:** OpenAI-compatible API with multiple providers
**Status:** Production-ready
**Why:** Unified API for all providers

**Integration:**
```bash
# Optional: Run omen as proxy
git clone https://github.com/ghostkellz/omen.git
cd omen
cargo build --release

# Start omen proxy
./target/release/omen --port 8080
```

**Reaper can use omen as unified endpoint:**
```toml
[providers.omen]
enabled = true
url = "http://localhost:8080"
# Omen handles routing to Claude, GPT, etc.
```

**Verdict:** Optional - reaper can talk directly to providers

---

## 📊 Dependency Priority

### Phase 1 (Weeks 1-2): Foundation
**Add these first:**
1. ✅ zsync (async runtime)
2. ✅ zrpc (gRPC server)
3. ✅ zlog (logging)
4. ✅ flare (configuration)
5. ✅ flash (CLI)

### Phase 2 (Weeks 3-4): Authentication
**Add these:**
6. ✅ zcrypto (OAuth, encryption)
7. ✅ ztime (timestamps, TTL)

### Phase 3 (Weeks 5-6): Providers
**Add these:**
8. ✅ zhttp (HTTP client)
9. ⚠️ zquic (HTTP/3 fallback)

### Phase 4 (Weeks 7-8): Completion
**Add these:**
10. ✅ rune (MCP integration)
11. ✅ zcrate (serialization)
12. ✅ zpack (compression)

### Phase 5 (Weeks 9-10): Agentic
**Already have:**
- rune (tool calling)
- zcrypto (secure execution)

### Phase 6 (Weeks 11-12): Integration
**Add these:**
13. ✅ phantom (TUI)
14. ✅ ghostspec (testing)

---

## 🔧 Integration Steps

### 1. Update build.zig.zon

```bash
# Navigate to project
cd /data/projects/reaper.grim

# Add all Tier 1 dependencies
zig fetch --save https://github.com/ghostkellz/zsync/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zrpc/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zlog/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zcrypto/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zhttp/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/rune/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/flare/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/flash/archive/refs/main.tar.gz

# Add Tier 2
zig fetch --save https://github.com/ghostkellz/phantom/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zcrate/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/ztime/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zregex/archive/refs/main.tar.gz

# Optional Tier 3
zig fetch --save https://github.com/ghostkellz/zquic/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/ghostspec/archive/refs/main.tar.gz
```

### 2. Update build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zsync = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });

    const zrpc = b.dependency("zrpc", .{
        .target = target,
        .optimize = optimize,
    });

    const zlog = b.dependency("zlog", .{
        .target = target,
        .optimize = optimize,
    });

    // ... add all others

    // Executable
    const exe = b.addExecutable(.{
        .name = "reaper",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link dependencies
    exe.root_module.addImport("zsync", zsync.module("zsync"));
    exe.root_module.addImport("zrpc", zrpc.module("zrpc"));
    exe.root_module.addImport("zlog", zlog.module("zlog"));
    // ... add all others

    b.installArtifact(exe);
}
```

### 3. Verify Build

```bash
zig build
# Should compile without errors
```

---

## 🎯 Integration Checklist

### Phase 1: Foundation ✅
- [ ] zsync integrated
- [ ] zrpc server running
- [ ] zlog logging working
- [ ] flare config loading
- [ ] flash CLI commands

### Phase 2: Auth ⏳
- [ ] zcrypto OAuth flows
- [ ] Vault storage
- [ ] Token management
- [ ] ztime for expiry

### Phase 3: Providers ⏳
- [ ] zhttp client
- [ ] rune MCP connection
- [ ] Provider interface
- [ ] zcrate serialization

### Phase 4: Features ⏳
- [ ] zpack compression
- [ ] phantom TUI
- [ ] zregex patterns
- [ ] ghostspec tests

---

## 📝 Notes

### Zig vs Rust Decision

**Reaper.grim is pure Zig** for these reasons:
1. ✅ **Consistency** - Grim editor is Zig, reaper is Zig, seamless integration
2. ✅ **Performance** - Zig matches Rust for raw speed, no GC
3. ✅ **Single language** - No polyglot complexity
4. ✅ **Direct integration** - Native Grim API access (no FFI)
5. ✅ **Ghost ecosystem** - 50+ Zig libraries already available
6. ✅ **Smaller binaries** - Zig produces tiny binaries (~12MB)

**Rust projects (optional add-ons):**
- **glyph**: Can run as separate MCP server (if needed)
- **omen**: Can run as unified API proxy (if needed)
- Both optional - reaper can work standalone in pure Zig

**Verdict:** Zig is the right move! 🦎

### phantom TUI Integration

**phantom provides Claude Code-style interface:**
- Chat panel in Grim editor
- Inline code suggestions (ghost text)
- Progress indicators for agentic tasks
- Diff previews for refactors
- Status line integration

**Rendering:**
- Native Grim TUI (via phantom)
- Async updates (zsync)
- Streaming responses (real-time)
- Beautiful, responsive UI

### Rust Projects (Optional)
- **glyph**: Can run as separate MCP server
- **omen**: Can run as unified API proxy
- Both optional - reaper can work standalone

### Dependency Management
- All Ghost projects use `zig fetch --save`
- No git submodules
- Clean dependency tree
- Fast incremental builds

### Version Compatibility
- All projects target Zig 0.16.0-dev
- Ensure compatibility before adding
- Check GitHub releases for updates

---

**Last Updated:** 2025-10-12
**Status:** Planning Phase
**Next:** Start adding Phase 1 dependencies
