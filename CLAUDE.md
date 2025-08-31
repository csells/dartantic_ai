# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dartantic is an agentic AI framework for Dart that provides easy integration with multiple AI providers (OpenAI, Google, Anthropic, Mistral, Cohere, Ollama). It features streaming output, typed responses, tool calling, embeddings, and MCP (Model Context Protocol) support.

The project is organized as a monorepo with multiple packages:
- `packages/dartantic_interface/` - Core interfaces and types
- `packages/dartantic_ai/` - Main implementation with provider integrations

## Development Commands

### Building and Testing
```bash
# Run all tests in the dartantic_ai package
cd packages/dartantic_ai && dart test

# Run a specific test file
cd packages/dartantic_ai && dart test test/specific_test.dart

# Run tests matching a name pattern
cd packages/dartantic_ai && dart test -n "pattern"

# Analyze code for issues
cd packages/dartantic_ai && dart analyze

# Format code
cd packages/dartantic_ai && dart format .

# Check formatting without making changes
cd packages/dartantic_ai && dart format --set-exit-if-changed .
```

### Package Management
```bash
# Get dependencies
cd packages/dartantic_ai && dart pub get

# Upgrade dependencies
cd packages/dartantic_ai && dart pub upgrade
```

## Architecture

### Core Components

1. **Agent** (`lib/src/agent/agent.dart`) - Main entry point that manages chat models, tool execution, and message orchestration. Supports model string parsing like "openai:gpt-4o" or "anthropic/claude-3-sonnet".

2. **Providers** (`lib/src/providers/`) - Each AI provider (OpenAI, Google, Anthropic, etc.) has its own implementation with standardized interfaces for chat and embeddings.

3. **Chat Models** (`lib/src/chat_models/`) - Provider-specific chat implementations with message mappers that convert between Dartantic's unified format and provider-specific formats.

4. **Embeddings Models** (`lib/src/embeddings_models/`) - Vector generation implementations for semantic search and similarity.

5. **Orchestrators** (`lib/src/agent/orchestrators/`) - Handle streaming responses, tool execution, and typed output processing.

### Key Design Patterns

- **Unified Message Format**: All providers use a common `ChatMessage` format with role-based messages (system, user, model) and support for multimodal content.

- **Tool Execution**: Automatic tool ID coordination for providers that don't supply IDs, with built-in error handling and retry logic.

- **Streaming State Management**: Uses `StreamingState` to accumulate responses and handle tool calls during streaming.

- **Provider Discovery**: Dynamic provider lookup through `Providers.get()` with support for aliases.

## Testing Strategy

- Tests use `validateMessageHistory()` helper to ensure proper message alternation (user/model/user/model)
- Integration tests connect to actual providers when API keys are available
- Mock tools and utilities in `test/test_tools.dart` and `test/test_utils.dart`

## Configuration

- Linting: Uses `all_lint_rules_community` with custom rules in `analysis_options.yaml`
- Formatter: 80-character page width