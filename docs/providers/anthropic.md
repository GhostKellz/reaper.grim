# Anthropic Provider Guide

## Overview

The Anthropic provider supports Claude models including Claude 3.5 Sonnet, Claude 3 Opus, and Claude 3 Haiku.

## Authentication

### Get API Key

1. Visit [Anthropic Console](https://console.anthropic.com)
2. Go to API Keys section
3. Create a new API key
4. Copy the key (starts with `sk-ant-`)

### Configure Reaper

```bash
reaper auth login anthropic
# Paste your API key when prompted
```

## Supported Models

### Claude 3.5 Sonnet (Recommended)

- **Model ID**: `claude-3-5-sonnet-20241022`
- **Context**: 200,000 tokens
- **Output**: 8,192 tokens
- **Features**: Functions (tools), Vision, Extended thinking
- **Cost**: $3/1M input, $15/1M output
- **Best for**: General-purpose, coding, analysis

```zig
const response = try provider.chat(
    messages,
    "claude-3-5-sonnet-20241022",
    8192,
    0.7,
);
```

### Claude 3 Opus

- **Model ID**: `claude-3-opus-20240229`
- **Context**: 200,000 tokens
- **Output**: 4,096 tokens
- **Features**: Functions, Vision, Highest intelligence
- **Cost**: $15/1M input, $75/1M output
- **Best for**: Complex reasoning, analysis, research

### Claude 3 Haiku

- **Model ID**: `claude-3-haiku-20240307`
- **Context**: 200,000 tokens
- **Output**: 4,096 tokens
- **Features**: Functions, Fast responses
- **Cost**: $0.25/1M input, $1.25/1M output
- **Best for**: Simple tasks, high-volume, low-latency

## Advanced Features

### Tool Use (Function Calling)

Claude has excellent tool use capabilities:

```zig
const tools = [_]Tool{
    .{
        .name = "web_search",
        .description = "Search the web for information",
        .input_schema = .{
            .type = "object",
            .properties = .{
                .query = .{ .type = "string", .description = "Search query" },
            },
        },
    },
};
```

### Vision

Claude 3 models support image analysis:

```zig
const messages = [_]Message{
    .{
        .role = "user",
        .content = [_]Content{
            .{ .type = "image", .source = .{ .type = "url", .url = "https://..." } },
            .{ .type = "text", .text = "Describe this image" },
        },
    },
};
```

### Extended Context

Claude excels at long-context tasks:

- Full 200K token window support
- Excellent recall across entire context
- Useful for large document analysis

## Rate Limits

Anthropic rate limits by tier:

| Tier | Requests/min | Tokens/min |
|------|--------------|------------|
| Free | 5 | 50,000 |
| Build Tier 1 | 50 | 100,000 |
| Build Tier 2 | 1,000 | 400,000 |

Configure accordingly:

```zig
const config = RateLimiterConfig{
    .max_tokens = 50,
    .refill_rate = 50 / 60,
};
```

## Error Handling

### Common Errors

**401 Unauthorized**:
- Invalid API key
- Solution: `reaper auth login anthropic`

**429 Rate Limited**:
- Exceeded limits
- Includes `Retry-After` header
- Solution: Built-in retry with exponential backoff

**529 Overloaded**:
- Service temporarily overloaded
- Solution: Automatic failover to backup provider

## Best Practices

1. **Model Selection**:
   - Use Haiku for simple, fast tasks
   - Use Sonnet for general-purpose work
   - Use Opus only when maximum intelligence needed

2. **Optimize Context**:
   - Claude handles long context well
   - Include relevant information early
   - Use clear instructions

3. **Tool Use**:
   - Claude is excellent at tool calling
   - Provide clear tool descriptions
   - Use structured outputs

4. **Cost Management**:
   - Haiku is very cost-effective
   - Sonnet offers best value for most tasks
   - Monitor token usage

## Example Usage

### Basic Chat

```zig
const messages = [_]Message{
    .{ .role = "user", .content = "Explain quantum computing" },
};

const response = try registry.chat(
    .anthropic,
    &messages,
    "claude-3-5-sonnet-20241022",
    4096,
    0.7,
);
```

### With System Prompt

```zig
const messages = [_]Message{
    .{ .role = "system", .content = "You are a helpful coding assistant" },
    .{ .role = "user", .content = "Write a binary search in Zig" },
};
```

### Long Document Analysis

```zig
// Claude excels at this
const messages = [_]Message{
    .{
        .role = "user",
        .content = large_document ++ "\n\nSummarize the key points.",
    },
};

const response = try registry.chat(
    .anthropic,
    &messages,
    "claude-3-5-sonnet-20241022",
    8192,
    0.5,  // Lower temperature for summarization
);
```

## Monitoring

```bash
# Check authentication
reaper auth status

# View provider health
reaper providers health anthropic
```

## Resources

- [Anthropic API Documentation](https://docs.anthropic.com)
- [Claude Model Comparison](https://www.anthropic.com/claude)
- [API Pricing](https://www.anthropic.com/pricing)
- [Tool Use Guide](https://docs.anthropic.com/claude/docs/tool-use)
