# Ollama Provider Guide

## Overview

Ollama provides local LLM inference with support for Llama, Mistral, DeepSeek, and many other open-source models. No API key required, runs entirely on your machine.

## Installation

### Install Ollama

```bash
# Linux
curl -fsSL https://ollama.com/install.sh | sh

# macOS
brew install ollama

# Docker
docker run -d -p 11434:11434 --name ollama ollama/ollama
```

### Pull Models

```bash
# Download models
ollama pull llama3
ollama pull deepseek-r1:32b
ollama pull mistral
ollama pull codellama

# List installed models
ollama list
```

## Authentication

Ollama runs locally and requires no authentication:

```bash
reaper auth login ollama
# No credentials needed - just confirms local connection
```

## Supported Models

### Llama 3 (Recommended)

- **Model ID**: `llama3:latest` or `llama3:70b`
- **Context**: 8K tokens
- **Parameters**: 8B or 70B
- **Best for**: General-purpose, fast local inference

```zig
const response = try registry.chat(
    .ollama,
    &messages,
    "llama3:latest",
    2048,
    0.7,
);
```

### DeepSeek R1

- **Model ID**: `deepseek-r1:32b`
- **Context**: 8K tokens
- **Parameters**: 32B
- **Best for**: Reasoning, code, mathematics

### Mistral

- **Model ID**: `mistral:latest`
- **Context**: 8K tokens
- **Parameters**: 7B
- **Best for**: Fast responses, efficiency

### Code Llama

- **Model ID**: `codellama:latest`
- **Context**: 16K tokens
- **Parameters**: 7B-34B
- **Best for**: Code generation, debugging

## Configuration

### Base URL

Default: `http://localhost:11434`

Custom:
```zig
try registry.registerOllama("http://192.168.1.100:11434");
```

### Model Discovery

Ollama dynamically discovers available models:

```zig
var provider = OllamaProvider.init(allocator, null);
const models = try provider.listModels();
defer allocator.free(models);

for (models) |model| {
    std.debug.print("Available: {s}\n", .{model});
}
```

## Performance

### Hardware Requirements

**Minimum** (7B models):
- 8GB RAM
- 4 CPU cores
- ~5GB disk per model

**Recommended** (32B models):
- 32GB RAM
- 8+ CPU cores
- GPU with 16GB+ VRAM (optional but much faster)

**Optimal** (70B models):
- 64GB RAM
- 16+ CPU cores
- GPU with 80GB VRAM

### Response Times

Local inference times (on Ryzen 9 7950X):

| Model | Tokens/sec | First Token |
|-------|------------|-------------|
| Llama 3 (8B) | ~40 | 200ms |
| DeepSeek (32B) | ~15 | 500ms |
| Llama 3 (70B) | ~8 | 1000ms |

With GPU (RTX 4090):

| Model | Tokens/sec | First Token |
|-------|------------|-------------|
| Llama 3 (8B) | ~120 | 50ms |
| DeepSeek (32B) | ~60 | 100ms |

## Features

### Local Inference

All processing happens locally:
- No internet required (after model download)
- Complete privacy
- No API costs
- Unlimited requests

### Model Management

```bash
# Pull new model
ollama pull llama3:70b

# Remove model
ollama rm mistral

# Update model
ollama pull llama3  # Gets latest version
```

### Multi-Model Support

Run multiple models:
```bash
# Terminal 1
ollama run llama3

# Terminal 2
ollama run codellama

# Both available via Reaper
```

## Best Practices

1. **Model Selection**:
   - Use 7B models for development
   - Use 32B models for production
   - Use code-specific models for programming

2. **Resource Management**:
   - Monitor RAM usage
   - One large model or multiple small ones
   - Use GPU if available

3. **Context Management**:
   - Most models have 8K context
   - Trim old messages
   - Use summarization for long conversations

4. **Cost Optimization**:
   - Free unlimited inference
   - Use for development/testing
   - Failover from paid APIs during rate limits

## Example Usage

### Simple Chat

```zig
const messages = [_]Message{
    .{ .role = "user", .content = "Explain recursion" },
};

const response = try registry.chat(
    .ollama,
    &messages,
    "llama3:latest",
    500,
    0.7,
);
```

### Code Generation

```zig
const messages = [_]Message{
    .{
        .role = "system",
        .content = "You are an expert programmer",
    },
    .{
        .role = "user",
        .content = "Write a quicksort in Zig",
    },
};

const response = try registry.chat(
    .ollama,
    &messages,
    "codellama:latest",
    2048,
    0.3,
);
```

### Fallback Provider

Use Ollama as fallback for rate-limited APIs:

```zig
const priorities = [_]ProviderPriority{
    .{ .kind = .anthropic, .priority = 1 },
    .{ .kind = .openai, .priority = 2 },
    .{ .kind = .ollama, .priority = 3 },  // Fallback
};

try failover_manager.setPriorities(&priorities);
```

## Docker Deployment

### Run in Container

```bash
# Start Ollama
docker run -d \
  -p 11434:11434 \
  -v ollama:/root/.ollama \
  --name ollama \
  ollama/ollama

# Pull models
docker exec -it ollama ollama pull llama3
docker exec -it ollama ollama pull deepseek-r1:32b
```

### With GPU Support

```bash
docker run -d \
  --gpus all \
  -p 11434:11434 \
  -v ollama:/root/.ollama \
  --name ollama \
  ollama/ollama
```

### Docker Compose

```yaml
version: '3'
services:
  ollama:
    image: ollama/ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  ollama:
```

## Troubleshooting

### "Connection refused"

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Start Ollama
ollama serve  # Or docker start ollama
```

### "Out of memory"

```bash
# Use smaller model
ollama pull llama3:8b  # Instead of llama3:70b

# Or increase swap
sudo dd if=/dev/zero of=/swapfile bs=1G count=32
```

### Slow responses

1. **Use GPU**: Install CUDA/ROCm drivers
2. **Reduce model size**: Use 7B instead of 70B
3. **Increase CPU cores**: Ollama uses all available cores
4. **Close other applications**: Free up RAM

## Model Comparison

| Model | Size | RAM | Speed | Quality | Best For |
|-------|------|-----|-------|---------|----------|
| Llama 3 (8B) | 4.7GB | 8GB | Fast | Good | General |
| Llama 3 (70B) | 40GB | 64GB | Slow | Excellent | Production |
| DeepSeek R1 (32B) | 18GB | 32GB | Medium | Great | Reasoning |
| Mistral (7B) | 4.1GB | 8GB | Fast | Good | Speed |
| CodeLlama (34B) | 19GB | 32GB | Medium | Great | Code |

## Resources

- [Ollama Official Site](https://ollama.com)
- [Model Library](https://ollama.com/library)
- [GitHub Repository](https://github.com/ollama/ollama)
- [API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)

## Integration Example

```zig
// Full example with health monitoring
var monitor = health.HealthMonitor.init(allocator, .{});
defer monitor.deinit();

var failover = failover.FailoverManager.init(allocator, .{}, &monitor);
defer failover.deinit();

// Set Ollama as fallback
const priorities = [_]ProviderPriority{
    .{ .kind = .openai, .priority = 1 },
    .{ .kind = .ollama, .priority = 2 },
};

try failover.setPriorities(&priorities);

// Automatic failover to Ollama if OpenAI fails
const response = try failover.executeWithFailover(
    CompletionResponse,
    ProviderError,
    &context,
    makeRequest,
);
```
