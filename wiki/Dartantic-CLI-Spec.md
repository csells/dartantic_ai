# Dartantic CLI Specification

This document specifies the design for a command-line interface (CLI) application that exposes Dartantic functionality to end users.

## Overview

The `dartantic` CLI provides a simple, scriptable interface for interacting with AI models through the Dartantic framework. Users can send prompts, configure agents, and receive responses directly from the terminal.

## Installation

The CLI will be distributed as an executable via:
- `dart pub global activate dartantic_cli`
- Pre-built binaries for major platforms

## Basic Usage

```bash
# Simple prompt using default agent (built-in provider)
dartantic -p "What is the capital of France?"

# Using a specific built-in provider
dartantic -a openai -p "Explain quantum computing"

# Using a custom agent defined in settings
dartantic -a coder -p "Write a function to sort an array"

# Streaming output (default)
dartantic -a anthropic -p "Tell me a story"

# Non-streaming output
dartantic -a google --no-stream -p "What is 2+2?"
```

## Command-Line Arguments

### Required Arguments

| Argument | Short | Description |
|----------|-------|-------------|
| `--prompt` | `-p` | The prompt text to send to the agent |

### Optional Arguments

| Argument | Short | Default | Description |
|----------|-------|---------|-------------|
| `--agent` | `-a` | `google` | Agent name (built-in provider or custom agent) |
| `--stream` | `-s` | `true` | Enable streaming output |
| `--no-stream` | | `false` | Disable streaming output |
| `--temperature` | `-t` | (agent default) | Model temperature (0.0-1.0) |
| `--thinking` | | `false` | Enable extended thinking/reasoning |
| `--output` | `-o` | (none) | Output file path (writes response to file) |
| `--json` | `-j` | `false` | Output in JSON format |
| `--verbose` | `-v` | `false` | Enable verbose logging |
| `--help` | `-h` | | Show help message |
| `--version` | | | Show version information |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DARTANTIC_AGENT` | Default agent name (overrides built-in default) |
| `DARTANTIC_LOG_LEVEL` | Logging level (FINE, INFO, WARNING, SEVERE, OFF) |
| `{PROVIDER}_API_KEY` | API keys for providers (e.g., `OPENAI_API_KEY`) |

## Agent Configuration

### Built-in Agents

All Dartantic providers are available as built-in agents that require no configuration:

| Agent Name | Provider | Default Model |
|------------|----------|---------------|
| `google` | Google AI | Provider default |
| `gemini` | Google AI (alias) | Provider default |
| `openai` | OpenAI | Provider default |
| `anthropic` | Anthropic | Provider default |
| `claude` | Anthropic (alias) | Provider default |
| `mistral` | Mistral AI | Provider default |
| `cohere` | Cohere | Provider default |
| `ollama` | Ollama | Provider default |
| `openrouter` | OpenRouter | Provider default |

Built-in agents use:
- The provider name as the agent name
- The provider's default model
- No system prompt

### Custom Agents (Settings File)

Custom agents are defined in `~/.dartantic/settings.yaml`:

```yaml
# ~/.dartantic/settings.yaml

# Default agent to use when --agent is not specified
default_agent: coder

# Custom agent definitions
agents:
  coder:
    model: anthropic:claude-sonnet-4-20250514
    system: |
      You are an expert software engineer. When writing code:
      - Use clear, descriptive variable names
      - Add comments for complex logic
      - Follow best practices for the language
      - Consider edge cases and error handling

  reviewer:
    model: openai:gpt-4o
    system: |
      You are a senior code reviewer. Review code for:
      - Correctness and potential bugs
      - Performance issues
      - Security vulnerabilities
      - Code style and readability
      Provide constructive feedback with specific suggestions.

  translator:
    model: google:gemini-2.5-flash
    system: You are a professional translator. Translate accurately while preserving tone and meaning.

  pirate:
    model: ollama:llama3.2
    system: You are a pirate. Respond to everything as a pirate would, using nautical terms and pirate speak. Arrr!

  minimal:
    model: mistral
    # No system prompt - uses model defaults
```

### Settings File Schema

```yaml
# Optional: Default agent when --agent not specified
# Falls back to 'google' if not set
default_agent: <agent-name>

# Agent definitions
agents:
  <agent-name>:
    # Required: Dartantic model string
    # Format: "provider", "provider:model", or "provider/model"
    model: <model-string>

    # Optional: System prompt for the agent
    # Can be a single line or multi-line YAML string
    system: <system-prompt>
```

### Agent Resolution Order

When resolving an agent name:

1. **Custom Agent**: Check `~/.dartantic/settings.yaml` for a matching agent name
2. **Built-in Provider**: Check if the name matches a built-in provider
3. **Error**: Throw an error if no matching agent is found

This order allows custom agents to override built-in provider names if desired.

## Output Behavior

### Standard Output (Default)

```bash
$ dartantic -a google -p "What is 2+2?"
4

Two plus two equals four.
```

### Streaming Output (Default)

Text streams to stdout as it's received from the model:

```bash
$ dartantic -a anthropic -p "Count to 5"
1... 2... 3... 4... 5!
```

### JSON Output (`--json`)

```bash
$ dartantic -a openai -p "What is the capital of France?" --json
{
  "output": "The capital of France is Paris.",
  "model": "openai:gpt-4o",
  "agent": "openai",
  "usage": {
    "inputTokens": 15,
    "outputTokens": 8
  }
}
```

### File Output (`--output`)

```bash
$ dartantic -a coder -p "Write a hello world program" -o hello.py
Response written to hello.py
```

## Error Handling

### Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Configuration error (invalid settings file) |
| 4 | API error (authentication, rate limits, etc.) |
| 5 | Network error |

### Error Output

Errors are written to stderr:

```bash
$ dartantic -a unknown -p "Hello"
Error: Agent 'unknown' not found.

Available agents:
  Built-in: google, openai, anthropic, mistral, cohere, ollama, openrouter
  Custom: coder, reviewer, translator

$ dartantic -a openai -p "Hello"
Error: OPENAI_API_KEY environment variable not set.
```

## Implementation Architecture

### Package Structure

```
packages/
  dartantic_cli/
    bin/
      dartantic.dart        # CLI entry point
    lib/
      src/
        cli_app.dart        # Main CLI application
        arg_parser.dart     # Argument parsing
        settings.dart       # Settings file loading
        agent_resolver.dart # Agent resolution logic
        output_handler.dart # Output formatting
    pubspec.yaml
    analysis_options.yaml
```

### Dependencies

```yaml
dependencies:
  args: ^2.5.0              # Argument parsing
  yaml: ^3.1.2              # Settings file parsing
  dartantic_ai:             # Core Dartantic functionality
    path: ../dartantic_ai
  path: ^1.9.0              # Path manipulation

dev_dependencies:
  test: ^1.25.0
  lints: ^2.1.0
```

### Core Components

#### CLI Entry Point

The entry point parses arguments and invokes the CLI application.

#### Settings Loader

Loads and validates `~/.dartantic/settings.yaml`, handling missing files gracefully.

#### Agent Resolver

Resolves agent names to Dartantic Agent instances:
1. Check custom agents from settings
2. Fall back to built-in providers
3. Apply system prompt from configuration

#### Output Handler

Handles different output modes:
- Streaming to stdout (default)
- JSON formatting
- File output

## Usage Examples

### Interactive Coding Assistant

```bash
# Use the coder agent for programming tasks
dartantic -a coder -p "Write a Dart function to calculate fibonacci numbers"
```

### Code Review

```bash
# Pipe code to the reviewer agent
cat myfile.dart | dartantic -a reviewer -p "Review this code"
```

### Translation

```bash
# Quick translation
dartantic -a translator -p "Translate to Spanish: Hello, how are you?"
```

### Local Model (Ollama)

```bash
# Use local Ollama model
dartantic -a ollama -p "Summarize the following text: ..."
```

### Scripting

```bash
# Use in shell scripts
RESPONSE=$(dartantic -a google --no-stream -p "Generate a random name")
echo "Generated name: $RESPONSE"
```

### JSON Processing

```bash
# Parse JSON output with jq
dartantic -a openai -p "List 3 colors" --json | jq '.output'
```

## Future Enhancements

The following features are candidates for future versions:

### Interactive Mode
```bash
dartantic -a coder --interactive
> What is recursion?
[response...]
> Give me an example
[response with context from previous turn...]
> /exit
```

### Conversation History
```bash
# Save conversation
dartantic -a coder -p "Hello" --save-history conversation.json

# Continue conversation
dartantic -a coder -p "Tell me more" --load-history conversation.json
```

### Typed Output
```bash
# Request structured JSON output
dartantic -a google -p "List 3 cities" --schema '{"type":"array","items":{"type":"string"}}'
```

### Attachments/Multimedia Input
```bash
# Send image with prompt
dartantic -a openai -p "Describe this image" --attach image.png
```

### Tool Usage
```bash
# Enable built-in tools
dartantic -a anthropic -p "What time is it?" --tools=datetime
```

### Stdin Input
```bash
# Read prompt from stdin
echo "What is Dart?" | dartantic -a google

# Pipe file content as context
cat README.md | dartantic -a coder -p "Summarize this documentation"
```

## Related Specifications

- [[Agent-Config-Spec]] - API key resolution and provider configuration
- [[Model-String-Format]] - Model string parsing specification
- [[Model-Configuration-Spec]] - Provider defaults and model resolution
