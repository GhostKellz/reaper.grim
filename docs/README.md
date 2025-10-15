# Reaper.grim Documentation

**Reaper.grim** is a high-performance, post-quantum secure LLM provider abstraction layer built in Zig. It provides unified access to multiple AI providers with advanced features like rate limiting, health monitoring, and automatic failover.

## Features

- 🔐 **Post-Quantum Secure**: Credentials stored in gvault with post-quantum encryption
- 🚀 **Multiple Providers**: OpenAI, Anthropic, xAI, Azure OpenAI, GitHub Copilot, Ollama
- 🔄 **Automatic Failover**: Intelligent provider switching with health monitoring
- ⚡ **Rate Limiting**: Token bucket algorithm with configurable limits
- 🔁 **Retry Logic**: Exponential backoff with jitter
- 📊 **Model Capabilities**: Automatic detection of model features and pricing
- 🌊 **Streaming Support**: Infrastructure for real-time token streaming
- 🛠️ **CLI Management**: Easy authentication and provider management

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/reaper.grim.git
cd reaper.grim

# Build with Zig 0.16+
zig build

# Install binary
zig build install
```

### Basic Usage

1. **Start the daemon**:
   ```bash
   reaper start
   ```

2. **Configure authentication**:
   ```bash
   # For API key providers (OpenAI, Anthropic, xAI)
   reaper auth login openai
   reaper auth login anthropic

   # For OAuth providers (GitHub Copilot)
   reaper auth login github-copilot

   # For local providers (Ollama)
   reaper auth login ollama
   ```

3. **Check authentication status**:
   ```bash
   reaper auth status
   ```

4. **List available providers**:
   ```bash
   reaper auth list
   ```

## Architecture

### Core Components

```
src/
├── providers/          # Provider implementations
│   ├── openai.zig     # OpenAI API
│   ├── claude.zig     # Anthropic Claude
│   ├── xai.zig        # xAI Grok
│   ├── azure.zig      # Azure OpenAI
│   ├── github_copilot.zig  # GitHub Copilot
│   ├── ollama.zig     # Local Ollama
│   ├── registry.zig   # Provider registry
│   ├── rate_limiter.zig   # Rate limiting
│   ├── health.zig     # Health monitoring
│   ├── failover.zig   # Failover logic
│   └── capabilities.zig   # Model capabilities
├── auth/              # Authentication
│   ├── vault.zig      # Secure credential storage
│   └── oauth_device.zig   # OAuth device flow
└── cli/               # Command-line interface
    └── commands.zig   # CLI commands
```

### Provider Flow

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│ ProviderRegistry    │
│ - Rate Limiting     │
│ - Health Checks     │
└──────┬──────────────┘
       │
       ▼
┌──────────────────────┐
│  FailoverManager     │
│  - Priority-based    │
│  - Round-robin       │
└──────┬───────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Provider (OpenAI/Claude/etc)   │
│  - API Request                  │
│  - Response Parsing             │
└─────────────────────────────────┘
```

## Configuration

### Vault Configuration

Reaper uses **gvault** for post-quantum encrypted credential storage:

- Default vault location: `~/.config/reaper/vault`
- Backend: Post-quantum encryption (Kyber, Dilithium)
- Namespace: `reaper`

### Rate Limiting

Configure rate limiting in your provider setup:

```zig
const config = RateLimiterConfig{
    .max_tokens = 60,        // Max requests in bucket
    .refill_rate = 1,        // Requests per second
    .max_retries = 3,        // Max retry attempts
    .base_delay_ms = 1000,   // Initial backoff delay
    .max_delay_ms = 60000,   // Maximum backoff delay
};
```

### Health Monitoring

Health check configuration:

```zig
const health_config = HealthCheckConfig{
    .check_interval_s = 60,         // Check every 60s
    .failure_threshold = 3,         // 3 failures = unhealthy
    .recovery_threshold = 2,        // 2 successes = recovered
    .timeout_ms = 5000,            // 5s timeout
    .degraded_threshold_ms = 2000, // >2s = degraded
};
```

### Failover Strategies

Available failover strategies:

- **Priority**: Try providers in priority order (default)
- **Round-robin**: Distribute load across healthy providers
- **Random**: Random selection from healthy providers
- **Weighted**: Weighted by response times (coming soon)

## Security

### Credential Storage

All credentials are stored in gvault with:
- **Post-quantum encryption** (Kyber-1024, Dilithium3)
- **BLAKE3 hashing** for integrity
- **Zeroization** of sensitive data
- **Encrypted at rest** with user passphrase

### OAuth Device Flow

GitHub Copilot uses OAuth 2.0 Device Authorization Flow:
1. Request device code
2. Display verification URL and code
3. Poll for access token
4. Store token in encrypted vault

## Performance

### Benchmarks

(Run on Linux 6.16, AMD Ryzen 9 7950X)

- Request latency: ~50-200ms (depending on provider)
- Rate limiter overhead: <1ms
- Health check overhead: <5ms
- Failover decision: <10ms

### Optimization Tips

1. **Use rate limiting** to avoid hitting API limits
2. **Enable health checks** for automatic failover
3. **Set appropriate timeouts** for your use case
4. **Use local Ollama** for development to save costs

## Provider Comparison

| Provider | Context | Output | Functions | Vision | Cost ($/1M in) |
|----------|---------|--------|-----------|--------|----------------|
| GPT-4 Turbo | 128K | 4K | ✓ | ✓ | $10.00 |
| GPT-4o | 128K | 4K | ✓ | ✓ | $5.00 |
| Claude 3.5 Sonnet | 200K | 8K | ✓ | ✓ | $3.00 |
| Grok 2 | 128K | 4K | ✓ | ✗ | $5.00 |
| Llama 3 (Ollama) | 8K | 2K | ✗ | ✗ | Free |

## Troubleshooting

### Common Issues

**Vault unlock fails**:
```bash
# Reset vault with new password
rm -rf ~/.config/reaper/vault
reaper auth login openai  # Will create new vault
```

**Provider authentication fails**:
```bash
# Check stored credentials
reaper auth status

# Re-authenticate
reaper auth login <provider>
```

**Rate limiting errors**:
- Increase `max_tokens` in rate limiter config
- Add delays between requests
- Use multiple providers with failover

## Development

### Building from Source

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

### Dependencies

- Zig 0.16+
- zhttp (HTTP client)
- gvault (secure storage)
- flash (CLI framework)
- zsync (async runtime)

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

See [LICENSE](../LICENSE) for details.

## Related Documentation

- [Provider Guides](providers/)
  - [OpenAI](providers/openai.md)
  - [Anthropic](providers/anthropic.md)
  - [xAI](providers/xai.md)
  - [Azure OpenAI](providers/azure.md)
  - [GitHub Copilot](providers/github-copilot.md)
  - [Ollama](providers/ollama.md)
- [API Reference](api/)
- [Examples](examples/)
