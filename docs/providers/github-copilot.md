# GitHub Copilot Provider Guide

## Overview

GitHub Copilot provides AI-powered code completion and chat through an OpenAI-compatible API. Authentication uses OAuth 2.0 Device Authorization Flow.

## Authentication

### Prerequisites

1. **GitHub Account** with Copilot subscription
2. **Active Copilot License**:
   - Individual ($10/month)
   - Business (contact GitHub)
   - Free for students/educators

### OAuth Device Flow

GitHub Copilot uses OAuth device flow (no browser redirect needed):

```bash
reaper auth login github-copilot
```

This will:
1. Display a verification URL and code
2. Prompt you to visit GitHub and enter the code
3. Poll for authorization
4. Store the access token securely

**Example output**:
```
GitHub Copilot Authentication
==============================

Please visit: https://github.com/login/device
And enter code: XXXX-XXXX

Waiting for authentication...

✓ Authentication successful!
```

### Manual Process

If you prefer manual OAuth:

1. Visit the displayed URL
2. Enter the verification code
3. Authorize "GitHub Copilot CLI"
4. Return to terminal (automatic)

## Supported Models

GitHub Copilot uses OpenAI models under the hood:

### GPT-4

- **Model ID**: `gpt-4`
- **Context**: Variable (typically 8K-32K)
- **Features**: Code generation, chat
- **Cost**: Included with Copilot subscription

### GPT-3.5 Turbo

- **Model ID**: `gpt-3.5-turbo`
- **Context**: 16K tokens
- **Features**: Fast responses, code completion
- **Cost**: Included with Copilot subscription

## API Endpoints

GitHub Copilot API:
- Base URL: `https://api.githubcopilot.com`
- Chat endpoint: `/chat/completions`
- Format: OpenAI-compatible

## Features

### Code Generation

```zig
const messages = [_]Message{
    .{
        .role = "user",
        .content = "Write a function to parse JSON in Zig",
    },
};

const response = try registry.chat(
    .github_copilot,
    &messages,
    "gpt-4",
    2048,
    0.3,
);
```

### Code Explanation

```zig
const messages = [_]Message{
    .{
        .role = "user",
        .content = "Explain this code:\n" ++ code_snippet,
    },
};
```

### Code Review

```zig
const messages = [_]Message{
    .{
        .role = "system",
        .content = "You are a code reviewer",
    },
    .{
        .role = "user",
        .content = "Review this pull request:\n" ++ diff,
    },
};
```

## Rate Limits

GitHub Copilot has generous limits:

- **Requests**: ~300/hour for individual
- **Tokens**: High (exact limits not publicly documented)
- **No per-token billing** (included in subscription)

Rate limiter config:
```zig
const config = RateLimiterConfig{
    .max_tokens = 300,
    .refill_rate = 5,  // 300/hour = 5/min
};
```

## Error Handling

### Common Errors

**401 Unauthorized**:
- Token expired (tokens expire after ~8 hours)
- No active Copilot subscription
- Solution: Re-authenticate with `reaper auth login github-copilot`

**403 Forbidden**:
- Copilot subscription inactive
- Solution: Check [GitHub billing](https://github.com/settings/billing)

**429 Rate Limited**:
- Exceeded hourly quota
- Solution: Wait or use failover to another provider

### Token Refresh

GitHub Copilot tokens expire. Handle automatically:

```zig
// Tokens expire after ~8 hours
// Re-authenticate when seeing 401 errors
```

## Best Practices

1. **Token Management**:
   - Tokens expire regularly
   - Monitor 401 errors
   - Re-authenticate as needed

2. **Use Cases**:
   - Excellent for code generation
   - Great for code explanation
   - Use for development workflows

3. **Failover**:
   - Set as secondary provider
   - Fall back to OpenAI/Anthropic for non-code tasks
   - Use for cost-effective development

4. **Context**:
   - Include relevant code context
   - Specify language/framework
   - Provide clear instructions

## Example Workflows

### Code Assistant

```zig
fn codeAssistant(registry: *ProviderRegistry, request: []const u8) ![]const u8 {
    const messages = [_]Message{
        .{
            .role = "system",
            .content = "You are an expert Zig programmer",
        },
        .{
            .role = "user",
            .content = request,
        },
    };

    const response = try registry.chat(
        .github_copilot,
        &messages,
        "gpt-4",
        4096,
        0.3,
    );

    return response.content;
}
```

### Diff Review

```zig
fn reviewDiff(registry: *ProviderRegistry, diff: []const u8) ![]const u8 {
    const prompt = try std.fmt.allocPrint(
        allocator,
        "Review this diff and suggest improvements:\n\n{s}",
        .{diff},
    );
    defer allocator.free(prompt);

    const messages = [_]Message{
        .{ .role = "user", .content = prompt },
    };

    const response = try registry.chat(
        .github_copilot,
        &messages,
        "gpt-3.5-turbo",
        2048,
        0.5,
    );

    return response.content;
}
```

## Security

### OAuth Security

- Uses official GitHub OAuth client ID
- Device flow (no client secret)
- Tokens stored in post-quantum encrypted vault
- Automatic token zeroization

### Token Storage

Location: `~/.config/reaper/vault`

```
reaper/github-copilot/default/access_token
```

Encryption:
- Kyber-1024 (post-quantum KEM)
- Dilithium3 (post-quantum signatures)
- BLAKE3 hashing

## Troubleshooting

### "No active subscription"

1. Visit [GitHub Copilot](https://github.com/features/copilot)
2. Subscribe or check existing subscription
3. Wait 5 minutes for activation
4. Re-authenticate

### "Token expired"

```bash
# Re-authenticate
reaper auth login github-copilot
```

### "Device code expired"

- You have 15 minutes to authorize
- If expired, restart authentication:
  ```bash
  reaper auth login github-copilot
  ```

## Monitoring

```bash
# Check token status
reaper auth status

# View last authentication
cat ~/.config/reaper/vault  # (encrypted)
```

## Comparison with Other Providers

| Feature | Copilot | OpenAI | Anthropic |
|---------|---------|--------|-----------|
| **Pricing** | Subscription | Pay-per-token | Pay-per-token |
| **Auth** | OAuth | API Key | API Key |
| **Best For** | Code | General | Analysis |
| **Token Cost** | Included | $5-30/1M | $3-75/1M |
| **Code Quality** | Excellent | Very Good | Very Good |

## Resources

- [GitHub Copilot](https://github.com/features/copilot)
- [API Documentation](https://docs.github.com/copilot)
- [OAuth 2.0 Device Flow](https://datatracker.ietf.org/doc/html/rfc8628)
- [Subscription Settings](https://github.com/settings/copilot)
