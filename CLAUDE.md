# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dartantic is an agentic AI framework for Dart that provides easy integration with multiple AI providers (OpenAI, Google, Anthropic, Mistral, Cohere, Ollama). It features streaming output, typed responses, tool calling, embeddings, and MCP (Model Context Protocol) support.

The project is organized as a monorepo with multiple packages:
- `packages/dartantic_interface/` - Core interfaces and types shared across all Dartantic packages
- `packages/dartantic_ai/` - Main implementation with provider integrations (primary development focus)

## Documentation

- **External Docs**: Full documentation at [docs.dartantic.ai](https://docs.dartantic.ai)
- **Wiki Documentation**: The `wiki/` folder contains comprehensive architecture documentation. See `wiki/Home.md` for the complete index of design documents, specifications, and implementation guides.
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

### Debugging
```bash
# Enable detailed logging via environment variable
DARTANTIC_LOG_LEVEL=FINE dart run example/bin/single_turn_chat.dart

# Log levels: SEVERE, WARNING, INFO, FINE (most verbose)
DARTANTIC_LOG_LEVEL=INFO dart test test/specific_test.dart
```

### Package Management
```bash
# Get dependencies
cd packages/dartantic_ai && dart pub get

# Upgrade dependencies
cd packages/dartantic_ai && dart pub upgrade
```

## Architecture

### Six-Layer Architecture

Dartantic uses a six-layer architecture with clear separation of concerns:

1. **API Layer** (`lib/src/agent/agent.dart`)
   - Thin coordination layer - main user-facing interface
   - Model string parsing and provider selection
   - Conversation state management
   - Public API contracts

2. **Orchestration Layer** (`lib/src/agent/orchestrators/`)
   - Complex workflow management (streaming, tool execution, typed output)
   - `DefaultStreamingOrchestrator` - Standard chat workflows
   - `TypedOutputStreamingOrchestrator` - Structured JSON output
   - `StreamingState` - Encapsulated mutable state per request
   - `ToolExecutor` - Centralized tool execution with error handling

3. **Provider Abstraction Layer** (`packages/dartantic_interface/`)
   - Clean contracts independent of implementation
   - Provider interface with capability declarations
   - ChatModel and EmbeddingsModel interfaces
   - Message and part types

4. **Provider Implementation Layer** (`lib/src/providers/`, `lib/src/chat_models/`, `lib/src/embeddings_models/`)
   - Provider-specific implementations isolated
   - Message mappers convert between Dartantic and provider formats
   - Protocol handlers for each provider's API
   - Each provider follows consistent structure:
     - Provider class (`providers/*_provider.dart`) - Factory for models
     - Chat model (`chat_models/*/`) - API communication and streaming
     - Message mappers (`chat_models/*/_message_mappers.dart`) - Format conversion
     - Options classes - Provider-specific configuration

5. **Infrastructure Layer** (`lib/src/shared/`)
   - Cross-cutting concerns (logging, HTTP retry, exceptions)
   - `RetryHttpClient` - Automatic retry with exponential backoff
   - `LoggingOptions` - Hierarchical logging configuration
   - Exception hierarchy

6. **Protocol Layer**
   - HTTP clients and direct API communication
   - Network-level operations

### Key Architectural Principles

- **Streaming-First Design**: All operations built on streaming foundation; process entire model stream before making decisions
- **Exception Transparency**: Never suppress exceptions; let errors bubble up with full context
- **Resource Management**: Direct model creation through providers; guaranteed cleanup via try/finally; simple disposal
- **State Isolation**: Each request gets its own `StreamingState` instance; no state leaks between requests
- **Provider Agnostic**: Same orchestrators work across all providers; provider quirks isolated in implementation layer

### Message Flow

Dartantic maintains clean request/response semantics:
```
User: Initial prompt
Model: Response with tool calls [toolCall1, toolCall2, toolCall3]
User: Tool results [result1, result2, result3]  // Single consolidated message
Model: Final synthesis response
```

Tool results are always consolidated into a single user message, never split across multiple messages. The orchestration layer handles accumulation during streaming and consolidation after execution.

### Model String Format

The Agent accepts flexible model string formats:
- `"openai"` - Provider only (uses defaults)
- `"openai:gpt-4o"` - Provider + chat model (legacy colon notation)
- `"openai/gpt-4o"` - Provider + chat model (slash notation)
- `"openai?chat=gpt-4o&embeddings=text-embedding-3-small"` - URI with query parameters

Parsed via `ModelStringParser` in `lib/src/agent/model_string_parser.dart`.

## Testing Strategy

- **ALWAYS check for existing tests before creating new ones** - Search the test directory for related tests using grep/glob before creating new test files. Update existing tests rather than duplicating functionality.
- Integration tests connect to actual providers when API keys are available (from environment variables or `~/global_env.sh`)
- Mock tools and utilities in `test/test_tools.dart` and `test/test_utils.dart`
- Focus on 80% cases; edge cases are documented but not exhaustively tested

### Capability-Based Provider Filtering

Tests use `requiredCaps` to filter providers by capability. This ensures tests only run against providers that support required features. The test infrastructure uses `ProviderTestCaps` (a test-only enum in `test/test_helpers/run_provider_test.dart`) to describe what capabilities each provider's default model supports:

```dart
// In test files, use runProviderTest with requiredCaps:
runProviderTest(
  'test description',
  (provider) async { /* test code */ },
  requiredCaps: {ProviderTestCaps.multiToolCalls},
);
```

See `ProviderTestCaps` in `test/test_helpers/run_provider_test.dart` for test capabilities. For runtime capability discovery, use `Provider.listModels()`.

## Configuration

- **Linting**: Uses `all_lint_rules_community` with custom overrides in `analysis_options.yaml`
  - Single quotes for strings
  - 80-character line width
  - `public_member_api_docs: true` for public APIs
  - `unnecessary_final: false` (finals are encouraged)
- **API Keys**: Sourced from environment variables or `~/global_env.sh` file
  - Pattern: `{PROVIDER}_API_KEY` (e.g., `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)
  - See `wiki/Agent-Config-Spec.md` for complete resolution logic

## Working with Providers

### Adding New Providers

1. Create provider class in `lib/src/providers/` extending `Provider`
2. Implement `createChatModel()` and optionally `createEmbeddingsModel()`
3. Create chat model in `lib/src/chat_models/<provider>_chat/`
4. Implement message mappers in `<provider>_message_mappers.dart`
5. Register provider factory in `Agent.providerFactories` in `lib/src/agent/agent.dart`
6. Add provider's test capabilities to `providerTestCaps` map in `test/test_helpers/run_provider_test.dart`
7. Create tests following existing patterns in `test/`

### Provider Structure

Each provider implementation includes:
- Provider factory class
- Chat model with streaming support
- Message mappers for bidirectional conversion
- Options class for provider-specific configuration
- Response model classes (if needed)

See `wiki/Provider-Implementation-Guide.md` for detailed guide.

## Important Implementation Notes

- **No Try-Catch in Examples**: Example apps are happy-path only; exceptions should propagate to expose issues
- **No Try-Catch in Tests**: Tests should fail on exceptions, not swallow them
- **No Try-Catch in Implementation**: Only catch exceptions to add context before re-throwing, never to suppress errors
- **Scratch Files**: Use `tmp/` folder at project root for temporary/test files
- **Silent Tests**: Successful tests produce no output; failures reported via `expect()`. Remove diagnostic `print()` statements before committing.