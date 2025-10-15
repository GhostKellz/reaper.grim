# OpenAI Provider Guide

## Overview

The OpenAI provider supports GPT-4, GPT-3.5, and other OpenAI models through the official API.

## Authentication

### Get API Key

1. Visit [OpenAI API Keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. Copy the key (starts with `sk-`)

### Configure Reaper

```bash
reaper auth login openai
# Paste your API key when prompted
```

For multiple accounts:
```bash
reaper auth login openai --account work
reaper auth login openai --account personal
```

## Supported Models

### GPT-4 Turbo

- **Model ID**: `gpt-4-turbo`
- **Context**: 128,000 tokens
- **Output**: 4,096 tokens
- **Features**: Functions, Vision, JSON mode
- **Cost**: $10/1M input, $30/1M output

```zig
const response = try provider.chat(messages, "gpt-4-turbo", 4096, 0.7);
```

### GPT-4o

- **Model ID**: `gpt-4o`
- **Context**: 128,000 tokens
- **Output**: 4,096 tokens
- **Features**: Functions, Vision, JSON mode, Audio
- **Cost**: $5/1M input, $15/1M output
- **Best for**: Multimodal tasks, faster responses

### GPT-3.5 Turbo

- **Model ID**: `gpt-3.5-turbo`
- **Context**: 16,384 tokens
- **Output**: 4,096 tokens
- **Features**: Functions, JSON mode
- **Cost**: $0.50/1M input, $1.50/1M output
- **Best for**: Simple tasks, high-volume requests

## Advanced Features

### Function Calling

```zig
// Function definitions will be added to request
const functions = [_]Function{
    .{
        .name = "get_weather",
        .description = "Get current weather",
        .parameters = .{
            .location = .{ .type = "string", .required = true },
        },
    },
};
```

### Vision (GPT-4 Turbo/4o only)

```zig
const messages = [_]Message{
    .{
        .role = "user",
        .content = .{
            .text = "What's in this image?",
            .image_url = "https://example.com/image.jpg",
        },
    },
};
```

### JSON Mode

Enable JSON mode by setting response format:
```zig
// JSON mode ensures valid JSON responses
request.response_format = .{ .type = "json_object" };
```

## Rate Limits

Default OpenAI rate limits:

| Tier | Requests/min | Tokens/min |
|------|--------------|------------|
| Free | 3 | 40,000 |
| Tier 1 | 500 | 200,000 |
| Tier 2 | 5,000 | 2,000,000 |

Configure rate limiter accordingly:

```zig
const config = RateLimiterConfig{
    .max_tokens = 500,  // RPM limit
    .refill_rate = 500 / 60,  // Per second
};
```

## Error Handling

### Common Errors

**401 Unauthorized**:
- Invalid API key
- Expired API key
- Solution: Re-authenticate with `reaper auth login openai`

**429 Rate Limited**:
- Exceeded rate limits
- Solution: Implement exponential backoff (built-in with retry logic)

**500/503 Server Error**:
- OpenAI service issues
- Solution: Enable failover to backup provider

### Retry Configuration

```zig
const retry_config = RateLimiterConfig{
    .max_retries = 3,
    .base_delay_ms = 1000,
    .max_delay_ms = 60000,
};
```

## Best Practices

1. **Use appropriate models**:
   - GPT-3.5 for simple tasks
   - GPT-4o for complex reasoning
   - GPT-4 Turbo for vision tasks

2. **Optimize token usage**:
   - Trim unnecessary context
   - Use smaller models when possible
   - Cache common responses

3. **Handle rate limits**:
   - Enable rate limiting
   - Implement request queuing
   - Use multiple API keys with failover

4. **Monitor costs**:
   - Track token usage
   - Set budget alerts in OpenAI dashboard
   - Use capability detection to estimate costs

## Example Usage

### Simple Chat

```zig
const messages = [_]Message{
    .{ .role = "user", .content = "Hello, how are you?" },
};

var registry = ProviderRegistry.init(allocator, vault);
try registry.registerOpenAI("default");

const response = try registry.chat(
    .openai,
    &messages,
    "gpt-3.5-turbo",
    500,
    0.7,
);
defer response.deinit(allocator);

std.debug.print("Response: {s}\n", .{response.content});
```

### With Retry and Failover

```zig
const result = try failover_manager.executeWithFailover(
    CompletionResponse,
    ProviderError,
    &context,
    makeRequest,
);
```

## Monitoring

Track OpenAI provider health:

```bash
# Check provider status
reaper auth status

# View health metrics (coming soon)
reaper providers health openai
```

## Resources

- [OpenAI API Documentation](https://platform.openai.com/docs)
- [OpenAI Pricing](https://openai.com/pricing)
- [OpenAI Status](https://status.openai.com)
- [Rate Limits Guide](https://platform.openai.com/docs/guides/rate-limits)
