# Reaper.grim TODO

**Version:** 0.1.0-alpha
**Last Updated:** 2025-10-12
**Status:** Project Kickoff

---

## 🎯 Project Vision

Build the **ultimate all-in-one AI coding assistant** for Grim editor in **pure Zig**, featuring:
- Autocompletes (Copilot-style)
- Agentic tasks (Claude Code-style)
- Multi-provider support (Ollama, OpenAI, Claude, Copilot)
- Modern gRPC communication
- OAuth integration (Google, GitHub)

---

## 📋 Phase 1: Foundation (Weeks 1-2)

### 1.1 Project Setup

- [ ] **Update build.zig**
  - Add Ghost ecosystem dependencies (zsync, zrpc, zlog, etc.)
  - Configure build options
  - Set up tests
  - Add examples target

- [ ] **Update build.zig.zon**
  - Add all required dependencies:
    ```
    zsync, zrpc, zlog, zcrypto, zquic, zhttp
    rune, flare, flash, phantom, zcrate
    ```
  - Use `zig fetch --save <url>` to add each

- [ ] **Create directory structure**
  ```
  src/
  ├── main.zig              # Entry point
  ├── root.zig              # Library root
  ├── server.zig            # gRPC server
  ├── auth/
  │   ├── google.zig        # Google OAuth
  │   ├── github.zig        # GitHub OAuth
  │   └── vault.zig         # Secure storage
  ├── providers/
  │   ├── provider.zig      # Provider interface
  │   ├── ollama.zig        # Ollama provider
  │   ├── openai.zig        # OpenAI provider
  │   ├── claude.zig        # Claude provider
  │   └── copilot.zig       # GitHub Copilot
  ├── completion/
  │   ├── engine.zig        # Completion engine
  │   ├── cache.zig         # Response cache
  │   └── context.zig       # Context gathering
  ├── agent/
  │   ├── planner.zig       # Task planner
  │   ├── executor.zig      # Step executor
  │   ├── tools.zig         # Tool registry
  │   └── verifier.zig      # Result verifier
  ├── rpc/
  │   ├── service.zig       # gRPC service definition
  │   └── handlers.zig      # Request handlers
  ├── context/
  │   ├── lsp.zig           # LSP context
  │   ├── git.zig           # Git context
  │   └── files.zig         # File context
  ├── config/
  │   └── config.zig        # Configuration via flare
  └── cli/
      └── commands.zig      # CLI via flash
  ```

- [ ] **Setup logging**
  - Initialize zlog
  - Configure log levels
  - Add structured logging helpers
  - Log rotation

- [ ] **Basic CLI**
  - Use flash framework
  - Implement `reaper --version`
  - Implement `reaper --help`
  - Implement `reaper start`
  - Implement `reaper stop`

### 1.2 Configuration System

- [ ] **Create reaper.toml schema**
  - Use flare for config management
  - Define all configuration options
  - Add defaults
  - Validation

- [ ] **Config locations**
  - `~/.config/reaper/reaper.toml` (user)
  - `/etc/reaper/reaper.toml` (system)
  - `./reaper.toml` (project-local)
  - Environment variables override

- [ ] **Config commands**
  - `reaper config get <key>`
  - `reaper config set <key> <value>`
  - `reaper config list`
  - `reaper config validate`

### 1.3 gRPC Server

- [ ] **Define service interface**
  - Use zrpc to define ReaperService
  - Completion RPC (streaming)
  - Agent RPC (bidirectional)
  - Chat RPC (bidirectional)

- [ ] **Implement server**
  - Start gRPC listener on 127.0.0.1:50051
  - Handle graceful shutdown
  - Connection pooling
  - Rate limiting

- [ ] **Basic health check**
  - `/health` endpoint
  - Return server status
  - Version info
  - Uptime

---

## 📋 Phase 2: Authentication (Weeks 3-4)

### 2.1 Secure Vault

- [ ] **Implement vault backend**
  - Use zcrypto for encryption
  - System keychain integration (Linux: libsecret, macOS: Keychain)
  - File-based fallback (encrypted)
  - In-memory cache

- [ ] **Vault API**
  ```zig
  pub fn store(key: []const u8, value: []const u8) !void
  pub fn get(key: []const u8) ![]const u8
  pub fn delete(key: []const u8) !void
  pub fn list() ![][]const u8
  ```

### 2.2 Google OAuth (for Claude)

- [ ] **OAuth client setup**
  - Register app at Google Cloud Console
  - Get client_id and client_secret
  - Configure redirect URI

- [ ] **Implement OAuth flow**
  - Start local callback server (port 8080)
  - Generate authorization URL
  - Open browser automatically
  - Handle callback
  - Exchange code for token
  - Store in vault

- [ ] **Token refresh**
  - Detect expired tokens
  - Auto-refresh using refresh_token
  - Update vault

- [ ] **CLI commands**
  - `reaper auth google`
  - `reaper auth google --status`
  - `reaper auth google --revoke`

### 2.3 GitHub OAuth (for Copilot)

- [ ] **Device flow implementation**
  - Request device code from GitHub
  - Display code to user
  - Poll for authorization
  - Store token in vault

- [ ] **CLI commands**
  - `reaper auth github`
  - `reaper auth github --status`
  - `reaper auth github --revoke`

### 2.4 API Key Management

- [ ] **Set API keys**
  - `reaper auth set-key openai sk-...`
  - `reaper auth set-key custom http://...`
  - Store securely in vault

- [ ] **Get API keys from commands**
  - Support `api_key_cmd = "pass openai-key"` in config
  - Execute command and capture output
  - Cache result

- [ ] **Auth status command**
  - `reaper auth status`
  - Show all providers and their auth status
  - ✓ Google: Authenticated as user@example.com
  - ✓ GitHub: Authenticated as username
  - ✓ OpenAI: API key set
  - ✗ Ollama: No auth required

---

## 📋 Phase 3: Provider System (Weeks 5-6)

### 3.1 Provider Interface

- [ ] **Define Provider trait**
  ```zig
  pub const Provider = struct {
      name: []const u8,
      model: []const u8,
      vtable: *const ProviderVTable,

      pub const ProviderVTable = struct {
          complete: *const fn (*Provider, Context) !CompletionResponse,
          chat: *const fn (*Provider, []Message) !ChatResponse,
          cost_per_token: *const fn (*Provider) f64,
          rate_limit: *const fn (*Provider) ?RateLimit,
      };
  };
  ```

- [ ] **Provider registry**
  - Register all providers at startup
  - Select provider based on strategy
  - Handle fallback on error

### 3.2 Ollama Provider (Simplest First)

- [ ] **HTTP client setup**
  - Use zhttp or zquic
  - POST to http://localhost:11434/api/generate
  - Parse JSON response

- [ ] **Completion method**
  - Send prompt
  - Receive response
  - Return as CompletionResponse

- [ ] **Test locally**
  - Start Ollama: `ollama serve`
  - Pull model: `ollama pull codellama:13b`
  - Test: `reaper complete "fn main() {"`

### 3.3 OpenAI Provider

- [ ] **API client**
  - POST to https://api.openai.com/v1/completions
  - Handle authentication (Bearer token)
  - Stream responses (SSE)

- [ ] **Models support**
  - gpt-4
  - gpt-3.5-turbo
  - Model selection from config

- [ ] **Error handling**
  - Rate limit errors (429)
  - Auth errors (401)
  - Retry logic

### 3.4 Claude Provider

- [ ] **API client**
  - POST to https://api.anthropic.com/v1/messages
  - Use Google OAuth token for auth
  - Stream responses

- [ ] **Models support**
  - claude-sonnet-4-5
  - claude-opus-4
  - claude-haiku-3-5

- [ ] **Message format**
  - Convert to Anthropic message format
  - Handle system prompts
  - Parse streaming deltas

### 3.5 GitHub Copilot Provider

- [ ] **API client**
  - POST to https://copilot-proxy.githubusercontent.com/v1/completions
  - Use GitHub OAuth token
  - Handle Copilot-specific format

- [ ] **Completion format**
  - prompt + suffix format
  - Parse choices array
  - Return first choice

### 3.6 Provider Selection

- [ ] **Selection strategies**
  - **auto**: Choose based on task complexity
  - **manual**: User specifies provider
  - **cheapest**: Optimize for cost
  - **fastest**: Optimize for latency
  - **fallback**: Auto-switch on error/rate limit

- [ ] **Cost tracking**
  - Track tokens used per provider
  - Calculate costs
  - Warn when approaching budget

---

## 📋 Phase 4: Completion Engine (Weeks 7-8)

### 4.1 Context Gathering

- [ ] **LSP context**
  - Integrate with rune (MCP)
  - Get symbols at cursor
  - Get type information
  - Get diagnostics

- [ ] **Git context**
  - Detect git repository
  - Get current branch
  - Get recent commits
  - Get diff for current file

- [ ] **File context**
  - Read current buffer
  - Find related files (imports)
  - Get project structure
  - Limit by token budget

### 4.2 Completion Request Handler

- [ ] **Implement gRPC handler**
  ```zig
  pub fn handleCompletion(
      request: CompletionRequest,
      stream: *zrpc.ServerStream,
  ) !void {
      // 1. Gather context
      const ctx = try gatherContext(request);

      // 2. Select provider
      const provider = try selectProvider(ctx);

      // 3. Request completion
      const result = try provider.complete(ctx);

      // 4. Stream response
      try stream.send(result);
  }
  ```

- [ ] **Debouncing**
  - Don't trigger on every keystroke
  - Wait for configurable delay (default 300ms)
  - Cancel previous request if new one comes in

### 4.3 Response Caching

- [ ] **Cache implementation**
  - LRU cache
  - Key: hash of (prompt, model, params)
  - Value: CompletionResponse
  - TTL: 5 minutes (configurable)

- [ ] **Cache invalidation**
  - On file save
  - On git status change
  - On manual clear

### 4.4 Streaming

- [ ] **Server-side streaming**
  - Stream tokens as they arrive from provider
  - Send deltas to client
  - Handle errors mid-stream

- [ ] **Client integration**
  - Grim receives tokens
  - Updates ghost text in real-time
  - Smooth UX

---

## 📋 Phase 5: Agentic Engine (Weeks 9-10)

### 5.1 Task Planner

- [ ] **Parse task description**
  - Extract intent (refactor, test, fix, etc.)
  - Identify target files/functions
  - Generate step-by-step plan

- [ ] **Plan generation**
  - Use Claude or GPT-4 for planning
  - Return list of concrete steps
  - Estimate time for each step

### 5.2 Tool Calling

- [ ] **Tool registry**
  - Define tool interface
  - Register built-in tools:
    - read_file
    - write_file
    - run_command
    - lsp_query
    - git_operation

- [ ] **Tool execution**
  - Parse tool call from LLM
  - Execute safely (sandbox?)
  - Return result to LLM
  - Log all tool calls

### 5.3 Step Executor

- [ ] **Execute plan**
  - Iterate through steps
  - Call LLM for each step
  - Handle tool calls
  - Stream progress to client

- [ ] **Error handling**
  - Retry failed steps
  - Replan if stuck
  - Report errors to user

### 5.4 Result Verifier

- [ ] **Verification checks**
  - Run tests (if applicable)
  - Check LSP diagnostics
  - Build project
  - Git status

- [ ] **Success criteria**
  - All tests pass
  - No new errors
  - Changes committed

---

## 📋 Phase 6: Integration (Weeks 11-12)

### 6.1 Grim Editor Integration

- [ ] **Native API**
  - Expose C ABI for Grim to call
  - Handle buffer updates
  - Cursor position changes
  - File events

- [ ] **Ghost text rendering**
  - Send completion to Grim
  - Grim renders as virtual text
  - Accept/reject keybindings

### 6.2 phantom.grim Plugin

- [ ] **Create reaper-client.gza**
  - Ghostlang wrapper around reaper
  - Handle gRPC communication
  - UI integration

- [ ] **Commands**
  - `:Reaper complete`
  - `:Reaper ask <question>`
  - `:Reaper execute <task>`

- [ ] **Keybindings**
  - `<Tab>` to accept
  - `<Esc>` to reject
  - `<leader>r` prefix for reaper commands

### 6.3 TUI Components

- [ ] **Use phantom framework**
  - Chat panel
  - Progress indicator
  - Notifications
  - Diff view

- [ ] **Status line integration**
  - Show reaper status
  - Provider indicator
  - Token usage

### 6.4 Testing

- [ ] **Unit tests**
  - Use ghostspec framework
  - Test all core functions
  - Mock providers

- [ ] **Integration tests**
  - End-to-end completion flow
  - Auth flows
  - gRPC communication

- [ ] **Performance tests**
  - Latency benchmarks
  - Memory usage
  - Concurrent requests

---

## 📋 Bonus Features (Future)

- [ ] **Voice input** (via Whisper API)
- [ ] **Image understanding** (GPT-4V, Claude with vision)
- [ ] **Code review** (PR analysis)
- [ ] **Commit message generation**
- [ ] **Documentation generation**
- [ ] **Test generation**
- [ ] **Refactoring suggestions**
- [ ] **Security scanning** (via AI)
- [ ] **Performance profiling** (AI-powered)
- [ ] **Multi-repo search** (semantic search across projects)

---

## 🚀 Getting Started

### Step 1: Setup Dependencies

```bash
cd /data/projects/reaper.grim

# Add all Ghost dependencies
zig fetch --save https://github.com/ghostkellz/zsync/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zrpc/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zlog/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zcrypto/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zquic/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zhttp/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/rune/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/flare/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/flash/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/phantom/archive/refs/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zcrate/archive/refs/main.tar.gz

# Update build.zig to use these dependencies
```

### Step 2: Basic Server

```bash
# Implement basic gRPC server
# src/server.zig

# Run
zig build run

# Test
curl http://localhost:50051/health
```

### Step 3: First Provider (Ollama)

```bash
# Implement Ollama provider (simplest)
# Test with local Ollama

ollama serve
ollama pull codellama:13b

# Test completion
./zig-out/bin/reaper complete "fn fibonacci(n: u32) u32 {"
```

### Step 4: Authentication

```bash
# Implement Google OAuth
reaper auth google

# Test with Claude API
reaper ask "How do I read a file in Zig?"
```

### Step 5: Grim Integration

```bash
# Create Grim plugin
# Test in grim editor

grim --plugin reaper-client.gza
```

---

## 📊 Success Metrics

| Milestone | Target Date | Status |
|-----------|-------------|--------|
| Phase 1 complete | Week 2 | 🚧 |
| Phase 2 complete | Week 4 | 📅 |
| Phase 3 complete | Week 6 | 📅 |
| Phase 4 complete | Week 8 | 📅 |
| Phase 5 complete | Week 10 | 📅 |
| Phase 6 complete | Week 12 | 📅 |
| v0.1.0 release | Week 12 | 📅 |

**Performance Targets:**
- ✅ Completion latency: <100ms
- ✅ gRPC round-trip: <5ms
- ✅ Memory usage: <100MB
- ✅ Auth flow: <30s
- ✅ Startup time: <1s

---

## 🎯 Next Immediate Actions

1. **Update build.zig.zon** - Add all Ghost dependencies
2. **Create directory structure** - Set up src/ folders
3. **Implement basic server** - Hello World gRPC server
4. **Add configuration** - Basic flare config loading
5. **Setup logging** - zlog integration
6. **CLI scaffold** - flash framework skeleton

**Start with:** `zig build` and get a clean compile!

---

**Last Updated:** 2025-10-12
**Status:** Ready to Start 🚀
**Team:** Ghost Ecosystem
