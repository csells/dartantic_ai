# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dartantic is an agentic AI framework for Dart that provides easy integration with multiple AI providers (OpenAI, Google, Anthropic, Mistral, Cohere, Ollama). It features streaming output, typed responses, tool calling, embeddings, and MCP (Model Context Protocol) support.

The project is organized as a monorepo with multiple packages:
- `packages/dartantic_interface/` - Core interfaces and types
- `packages/dartantic_ai/` - Main implementation with provider integrations

## Documentation Guidelines

- **Design documents should NOT include code implementations** - Specifications in the `wiki/` folder should describe algorithms, data flow, and architecture without including actual code, as code in documentation immediately goes stale. Implementation details belong in the code itself, not in design docs.

## Development Commands

### Building and Testing
```bash
# Run all tests in the dartantic_ai package
cd packages/dartantic_ai && dart test

# Run a specific test file
cd packages/dartantic_ai && dart test test/specific_test.dart

# Run tests matching a name pattern
cd packages/dartantic_ai && dart test -n "pattern"

# Run a single test by name
cd packages/dartantic_ai && dart test -n "test name"

# Analyze code for issues
cd packages/dartantic_ai && dart analyze

# Format code
cd packages/dartantic_ai && dart format .

# Check formatting without making changes
cd packages/dartantic_ai && dart format --set-exit-if-changed .
```

### Running Examples
```bash
# Run example files (from dartantic_ai package)
cd packages/dartantic_ai && dart run example/bin/single_turn_chat.dart
cd packages/dartantic_ai && dart run example/bin/typed_output.dart
cd packages/dartantic_ai && dart run example/bin/tool_calling.dart
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

### Provider Implementation Structure

Each provider follows a consistent pattern:
- **Provider class** (`providers/*_provider.dart`) - Factory for creating chat and embedding models
- **Chat model** (`chat_models/*/`_chat_model.dart`) - Handles chat completions and streaming
- **Message mappers** (`chat_models/*/`_message_mappers.dart`) - Converts between Dartantic and provider formats
- **Options classes** (`*_options.dart`) - Provider-specific configuration

## Testing Strategy

- Tests use `validateMessageHistory()` helper to ensure proper message alternation (user/model/user/model)
- Integration tests connect to actual providers when API keys are available
- Mock tools and utilities in `test/test_tools.dart` and `test/test_utils.dart`

## Configuration

- Linting: Uses `all_lint_rules_community` with custom rules in `analysis_options.yaml`
- Formatter: 80-character page width

## Working with New Providers

When implementing a new provider:
1. Create provider class in `lib/src/providers/`
2. Implement chat model in `lib/src/chat_models/<provider>_chat/`
3. Create message mappers for converting between Dartantic and provider formats
4. Add provider to `Providers.get()` registry
5. Write tests following existing patterns in `test/`

## Current Development

The project is actively developing OpenAI Responses API support via the `openai_core` package. See:
- `lib/src/providers/openai_responses_provider.dart` - Responses provider implementation
- `plans/responses-provider-*.md` - Design documents and requirements