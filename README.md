# Reaper.grim

<div align="center">
  <img src="assets/reaper-logo.png" alt="Reaper.grim - You Reap What You Sow" width="256" height="256">

**Experimental AI Development Tool for Grim Editor**
*Pure Zig | Multi-Provider | OAuth | gRPC | Async*

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-yellow?logo=zig&style=for-the-badge)
![Pure Zig](https://img.shields.io/badge/100%25-Pure%20Zig-F7A41D?style=for-the-badge&logo=zig)
![Grim](https://img.shields.io/badge/Editor-Grim-gray?style=for-the-badge)
![Ghost Ecosystem](https://img.shields.io/badge/Ghost-Ecosystem-7FFFD4?style=for-the-badge)

![AI Powered](https://img.shields.io/badge/AI-Powered-FF6B6B?style=for-the-badge)
![Multi Provider](https://img.shields.io/badge/Multi-Provider-5B21B6?style=for-the-badge)
![gRPC](https://img.shields.io/badge/Protocol-gRPC-00ADD8?style=for-the-badge&logo=grpc)
![Async](https://img.shields.io/badge/Async-zsync-orange?style=for-the-badge)

[![License](https://img.shields.io/github/license/ghostkellz/reaper.grim?style=for-the-badge&color=ee999f)](LICENSE)
![Status](https://img.shields.io/badge/Status-Experimental-red?style=for-the-badge)
[![Stars](https://img.shields.io/github/stars/ghostkellz/reaper.grim?style=for-the-badge&color=FFD700)](https://github.com/ghostkellz/reaper.grim/stargazers)

</div>

---

## ⚠️ EXPERIMENTAL - EARLY ALPHA

> **WARNING:** Reaper.grim is in **very early development**. This is a **research project** and **experimental testing library** for exploring AI-powered coding workflows in pure Zig.
>
> - 🚧 **Not production ready**
> - 🧪 **APIs will change**
> - 🐛 **Expect bugs**
> - 📝 **Limited documentation**
> - 🔨 **Actively under construction**
>
> **Use at your own risk!** This is a testing ground for ideas that may or may not work.

---

## 🎯 Vision

Reaper.grim aims to be an **all-in-one AI coding assistant** built in **pure Zig** for the **Grim editor**, exploring what's possible when you combine:
- 🤖 **Multi-provider AI** - Copilot, Claude, GPT, Ollama, and more
- ⚡ **Native performance** - Pure Zig, <100ms latency
- 🔐 **Modern auth** - OAuth (Google, GitHub) not just API keys
- 🚀 **gRPC communication** - Modern, fast, streaming
- 🧠 **Agentic capabilities** - Multi-step autonomous tasks

**"You reap what you sow"** - Better code, better context, better AI.

---

## 🌟 Planned Features

**If successful, Reaper will provide:**

### 1. **Copilot-Level Autocompletes**
```zig
fn fibonacci(n: u32) u32 {
    |if (n <= 1) return n;|  ← Ghost text suggestions
    |return fibonacci(n - 1) + fibonacci(n - 2);|
}
```
- Real-time completions (<100ms)
- Multi-line suggestions
- Context-aware (LSP, git, files)
- Multiple providers (Copilot, Claude, GPT, Ollama)

### 2. **Agentic Multi-Step Tasks**
```
You: "Add comprehensive tests for this module"

Reaper:
  ✓ Analyzing module structure...
  ✓ Identified 15 testable functions
  ✓ Writing tests/parser.test.zig...
  ✓ Running tests... (all passing)

Result: Added 47 tests (100% coverage)
```
- Autonomous code generation
- Tool calling (files, LSP, git, shell)
- Plan-execute-verify workflow
- Progress streaming

### 3. **Advanced Chat Interface**
- Conversational AI about your codebase
- Code explanations and refactoring
- One-click apply changes
- Persistent conversation history

### 4. **Multi-Provider Support**
| Provider | Auth | Use For |
|----------|------|---------|
| **GitHub Copilot** | OAuth | Fast autocompletes |
| **Claude** | Google OAuth | Complex tasks |
| **OpenAI** | API Key | General purpose |
| **Ollama** | None | Local/private |
| **Custom** | Config | Self-hosted |

**Auto-selection:** Reaper picks best provider for each task
**Fallback:** Auto-switch on rate limits/errors

### 5. **Modern OAuth**
```bash
$ reaper auth google    # Sign in with Google (Claude)
$ reaper auth github    # Sign in with GitHub (Copilot)
```
- Secure token storage (encrypted vault)
- Auto token refresh
- No plaintext API keys

### 6. **Pure Zig Performance**
- **Fast:** <1s startup, <100ms completions
- **Small:** <100MB memory, ~12MB binary
- **Modern:** gRPC (not HTTP), async (zsync)

---

## 🏗️ Architecture

**Built on Ghost Ecosystem:**

```
Reaper.grim (Pure Zig)
├── zsync (async runtime)
├── zrpc (gRPC framework)
├── zlog (structured logging)
├── zcrypto (OAuth & encryption)
├── zquic (HTTP/3 client)
├── rune (MCP integration)
├── flare (configuration)
├── flash (CLI framework)
└── phantom (TUI components)
```

**Design Goals:**
- **Modular** - Clean separation of concerns
- **Async-first** - All I/O is non-blocking
- **Streaming** - Real-time responses
- **Secure** - OAuth, encrypted storage
- **Fast** - Native Zig performance

---

## 📚 Documentation

- **[GRIM_SPECS.md](GRIM_SPECS.md)** - Full technical specifications
- **[TODO.md](TODO.md)** - Development roadmap & tasks
- **[GHOST_INTEGRATIONS.md](GHOST_INTEGRATIONS.md)** - Ghost ecosystem libraries

---

## 🚀 Quick Start (When Ready)

**Not yet functional! Coming soon:**

```bash
# 1. Clone
git clone https://github.com/ghostkellz/reaper.grim.git
cd reaper.grim

# 2. Build
zig build -Drelease-safe

# 3. Install
sudo cp zig-out/bin/reaper /usr/local/bin/

# 4. Authenticate
reaper auth google    # For Claude
reaper auth github    # For Copilot

# 5. Start daemon
reaper start

# 6. Test
reaper complete "fn main() {"
```

---

## ⚙️ Configuration (Planned)

**reaper.toml:**
```toml
[daemon]
address = "127.0.0.1:50051"
log_level = "info"

[modes]
completion = true   # Autocompletes
agent = true        # Multi-step tasks
chat = true         # Chat interface

[providers.copilot]
enabled = true
auth = "github_oauth"
priority = 1

[providers.claude]
enabled = true
auth = "google_oauth"
model = "claude-sonnet-4-5"
priority = 2

[providers.ollama]
enabled = true
url = "http://localhost:11434"
models = ["codellama:13b"]
priority = 3
```

---

## 🎯 Comparison with Existing Tools

**Goal:** Learn from the best, combine their strengths:

| Feature | Reaper (Goal) | Claude Code | Copilot | Cursor |
|---------|---------------|-------------|---------|--------|
| **Language** | Pure Zig | Python/Node | ? | Electron |
| **Providers** | 5+ | 1 (Claude) | 1 (Copilot) | 2 |
| **Autocomplete** | ✓ Goal | ✗ | ✓ | ✓ |
| **Agentic** | ✓ Goal | ✓ | ✗ | ⚠️ |
| **OAuth** | ✓ Goal | ✗ | ✓ | ✗ |
| **Protocol** | gRPC | HTTP | HTTP | HTTP |
| **Editor** | Grim | Any | VS Code | Cursor |
| **Open Source** | ✓ MIT | ✗ | ✗ | ✗ |

**Not claiming superiority** - just different approach and goals!

---

## 🛣️ Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] Project skeleton
- [ ] gRPC server (zrpc)
- [ ] Configuration (flare)
- [ ] Logging (zlog)
- [ ] Basic CLI (flash)

### Phase 2: Authentication (Weeks 3-4)
- [ ] Google OAuth (Claude)
- [ ] GitHub OAuth (Copilot)
- [ ] Secure vault (zcrypto)
- [ ] Token management

### Phase 3: Providers (Weeks 5-6)
- [ ] Ollama (local)
- [ ] OpenAI API
- [ ] Claude API
- [ ] Copilot API
- [ ] Provider selection

### Phase 4: Completion Engine (Weeks 7-8)
- [ ] Context gathering
- [ ] Request handling
- [ ] Response streaming
- [ ] Caching

### Phase 5: Agentic Engine (Weeks 9-10)
- [ ] Task planner
- [ ] Tool calling
- [ ] Step executor
- [ ] Result verifier

### Phase 6: Integration (Weeks 11-12)
- [ ] Grim integration
- [ ] TUI components
- [ ] Testing
- [ ] Documentation

**Current Status:** Phase 1 (skeleton project)

---

## 🤝 Contributing

**Want to help test/build this?**

See [TODO.md](TODO.md) for concrete tasks you can tackle!

**Ways to help:**
- 🧪 Test and report bugs
- 📝 Improve documentation
- 🔧 Implement features
- 💡 Suggest improvements
- ⭐ Star the repo!

**Remember:** This is **experimental** - expect things to break!

---

## 📊 Development Status

| Component | Status | Notes |
|-----------|--------|-------|
| Project skeleton | ✅ Done | Basic structure |
| gRPC server | 📅 Planned | Phase 1 |
| Configuration | 📅 Planned | Phase 1 |
| OAuth (Google/GitHub) | 📅 Planned | Phase 2 |
| Providers | 📅 Planned | Phase 3 |
| Completion engine | 📅 Planned | Phase 4 |
| Agentic engine | 📅 Planned | Phase 5 |
| Grim integration | 📅 Planned | Phase 6 |

**Estimated completion:** 12 weeks (optimistic!)

---

## ⚖️ Disclaimer

> **This is a research/testing project.**
>
> - May not reach completion
> - APIs will change without notice
> - No stability guarantees
> - Limited support
> - Use at your own risk
>
> **Not recommended for production use** (yet!)

---

## 🙏 Credits

**Inspired by:**
- **[Claude Code](https://www.anthropic.com/claude-code)** - Agentic workflows
- **[GitHub Copilot](https://github.com/features/copilot)** - Autocomplete UX
- **[Cursor](https://cursor.sh/)** - Chat interface
- **[Continue.dev](https://continue.dev/)** - Multi-provider approach

**Built with Ghost Ecosystem:**
- **[Grim](https://github.com/ghostkellz/grim)** - The editor
- **[phantom.grim](https://github.com/ghostkellz/phantom.grim)** - Config framework
- **[zsync](https://github.com/ghostkellz/zsync)** - Async runtime
- **[zrpc](https://github.com/ghostkellz/zrpc)** - gRPC framework
- **[+20 more Ghost libraries](GHOST_INTEGRATIONS.md)**

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

<div align="center">

**Built with 💀 by the Ghost Ecosystem**

[Grim](https://github.com/ghostkellz/grim) •
[Ghostlang](https://github.com/ghostkellz/ghostlang) •
[Phantom.grim](https://github.com/ghostkellz/phantom.grim)

⭐ **Star if you're interested!** ⭐

*"You reap what you sow"* - Reaper.grim

**Experimental AI Research Project** 🧪

</div>
