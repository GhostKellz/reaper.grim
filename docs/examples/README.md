# Reaper.grim Examples

This directory contains example code demonstrating various features of Reaper.grim.

## Examples

### 1. Basic Chat (`basic_chat.zig`)

Simple example showing basic provider usage:
- Initialize vault
- Register provider
- Make chat request
- Handle response

**Run:**
```bash
zig build-exe basic_chat.zig --dep reaper_grim
./basic_chat
```

### 2. Failover Setup (`failover_setup.zig`)

Advanced example demonstrating:
- Multiple provider registration
- Health monitoring
- Automatic failover
- Priority-based provider selection
- Health status reporting

**Key concepts:**
- `HealthMonitor`: Tracks provider health
- `FailoverManager`: Handles automatic provider switching
- `ProviderPriority`: Defines fallback order

**Run:**
```bash
zig build-exe failover_setup.zig --dep reaper_grim
./failover_setup
```

### 3. Rate Limiting (`rate_limiting.zig`)

Demonstrates rate limiting and retry logic:
- Token bucket rate limiter
- Exponential backoff with jitter
- Automatic retry on transient errors
- Non-blocking token acquisition

**Key concepts:**
- `RateLimiter`: Token bucket algorithm
- `RetryContext`: Exponential backoff
- `withRetry`: Automatic retry wrapper

**Run:**
```bash
zig build-exe rate_limiting.zig --dep reaper_grim
./rate_limiting
```

### 4. Capability Detection (`capability_detection.zig`)

Shows model capability detection:
- Query model features
- Find models by requirements
- Compare costs
- Estimate request costs

**Key concepts:**
- `CapabilityRegistry`: Model metadata
- `ModelCapabilities`: Feature detection
- Cost estimation

**Run:**
```bash
zig build-exe capability_detection.zig --dep reaper_grim
./capability_detection
```

## Common Patterns

### Vault Setup

All examples use gvault for secure credential storage:

```zig
var vault_instance = try vault.Vault.init(allocator, .{
    .backend = .gvault,
    .namespace = "reaper",
});
defer vault_instance.deinit();

try vault_instance.unlock("your-passphrase");
```

**Environment variable:**
```bash
export REAPER_VAULT_PASS="your-secure-passphrase"
```

### Provider Registration

```zig
var provider_registry = registry.ProviderRegistry.init(allocator, &vault_instance);
defer provider_registry.deinit();

// API key providers
try provider_registry.registerOpenAI("default");
try provider_registry.registerAnthropic("default");

// OAuth providers
try provider_registry.registerGitHubCopilot("default");

// Local providers
try provider_registry.registerOllama(null);
```

### Making Requests

```zig
const messages = [_]http.Message{
    .{ .role = "user", .content = "Your prompt here" },
};

var response = try provider_registry.chat(
    .openai,                 // Provider
    &messages,              // Messages
    "gpt-3.5-turbo",       // Model
    1000,                  // Max tokens
    0.7,                   // Temperature
);
defer response.deinit(allocator);

std.debug.print("{s}\n", .{response.content});
```

## Build Configuration

### Single Example

```bash
zig build-exe example_name.zig \
  --dep reaper_grim \
  --dep zsync \
  --dep zhttp \
  --dep gvault \
  --dep flash
```

### All Examples

Create `build.zig` in this directory:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const examples = [_][]const u8{
        "basic_chat",
        "failover_setup",
        "rate_limiting",
        "capability_detection",
    };

    for (examples) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = .{ .path = b.fmt("{s}.zig", .{name}) },
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("reaper_grim", b.dependency("reaper_grim", .{}).module("reaper_grim"));

        b.installArtifact(exe);
    }
}
```

Then:
```bash
zig build
```

## Environment Setup

### Required Credentials

Before running examples, authenticate with providers:

```bash
# API key providers
reaper auth login openai
reaper auth login anthropic
reaper auth login xai

# OAuth providers
reaper auth login github-copilot

# Local (no auth needed)
reaper auth login ollama
```

### Verify Setup

```bash
reaper auth status
```

Expected output:
```
Vault Status: UNLOCKED
Backend: gvault (post-quantum encrypted)

Provider Authentication Status:
  OpenAI               ✓ AUTHENTICATED
  Anthropic            ✓ AUTHENTICATED
  xAI                  ✓ AUTHENTICATED
  Azure OpenAI         ✗ Not configured
  GitHub Copilot       ✓ AUTHENTICATED
  Ollama               ✓ AUTHENTICATED
```

## Next Steps

1. **Start with `basic_chat.zig`** to understand core concepts
2. **Explore `failover_setup.zig`** for production patterns
3. **Study `rate_limiting.zig`** for high-volume use cases
4. **Review `capability_detection.zig`** for model selection

## Troubleshooting

### "Vault locked" error

```bash
export REAPER_VAULT_PASS="your-passphrase"
```

Or unlock manually:
```bash
reaper auth status  # Will prompt for passphrase
```

### "Provider not authenticated" error

```bash
reaper auth login <provider>
```

### "Rate limit exceeded" error

Adjust rate limiter config:
```zig
const config = RateLimiterConfig{
    .max_tokens = 500,     // Increase bucket size
    .refill_rate = 10,     // Increase refill rate
};
```

## Documentation

- [Main Documentation](../README.md)
- [Provider Guides](../providers/)
- [API Reference](../api/)

## Contributing

Have a useful example? Submit a PR!

1. Create new example file
2. Add to this README
3. Test thoroughly
4. Submit PR with description
