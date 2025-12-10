This document defines the model string parsing system for dartantic 1.0, including the supported formats and parsing behavior.

## Overview

The `ModelStringParser` class extracts provider, chat model, embeddings model, and media model names from a string input. It supports multiple formats for flexibility and backward compatibility.

## Supported Formats

| Format | Example | Parsed Output |
|--------|---------|---------------|
| **Provider Only** | `providerName` | provider: `providerName`, chat: `null`, embeddings: `null`, media: `null` |
| **Provider + Chat (colon)** | `providerName:chatModelName` | provider: `providerName`, chat: `chatModelName`, embeddings: `null`, media: `null` |
| **Provider + Chat (slash)** | `providerName/chatModelName` | provider: `providerName`, chat: `chatModelName`, embeddings: `null`, media: `null` |
| **Query Parameters** | `providerName?chat=chatModel&embeddings=embeddingsModel` | provider: `providerName`, chat: `chatModel`, embeddings: `embeddingsModel`, media: `null` |
| **All Three Models** | `providerName?chat=chatModel&embeddings=embeddingsModel&media=mediaModel` | provider: `providerName`, chat: `chatModel`, embeddings: `embeddingsModel`, media: `mediaModel` |

## URI-Based Parsing

The parser leverages Dart's `Uri` class for robust parsing of various model string formats.

## String Building

The `toString()` method builds strings based on the components using URI formatting.

## Examples

### Basic Usage

```dart
// Provider only - uses all defaults
final parser1 = ModelStringParser.parse('openai');
// provider: 'openai', chat: null, embeddings: null, media: null

// Legacy format with chat model
final parser2 = ModelStringParser.parse('openai:gpt-4o');
// provider: 'openai', chat: 'gpt-4o', embeddings: null, media: null

// Slash format
final parser3 = ModelStringParser.parse('openai/gpt-4o');
// provider: 'openai', chat: 'gpt-4o', embeddings: null, media: null

// Query parameter format with two models
final parser4 = ModelStringParser.parse('openai?chat=gpt-4o&embeddings=text-embedding-3-small');
// provider: 'openai', chat: 'gpt-4o', embeddings: 'text-embedding-3-small', media: null

// All three model types
final parser5 = ModelStringParser.parse('openai?chat=gpt-4o&embeddings=text-embedding-3-small&media=dall-e-3');
// provider: 'openai', chat: 'gpt-4o', embeddings: 'text-embedding-3-small', media: 'dall-e-3'
```

### Agent Integration

```dart
// Simple provider
final agent1 = Agent('openai');
// Uses default chat, embeddings, and media models

// Specific chat model
final agent2 = Agent('openai:gpt-4o');
// Uses gpt-4o for chat, defaults for embeddings and media

// Different models for each operation
final agent3 = Agent('openai?chat=gpt-4o&embeddings=text-embedding-3-large&media=dall-e-3');
// Explicit models for all operations
```

## Edge Cases

| Input | Provider | Chat Model | Embeddings Model | Media Model |
|-------|----------|------------|------------------|-------------|
| `""` (empty) | Throws exception | - | - | - |
| `"provider:"` | `"provider"` | `null` | `null` | `null` |
| `"provider//"` | `"provider"` | `""` | `null` | `null` |
| `"provider?chat="` | `"provider"` | `null` | `null` | `null` |
| `"provider?chat=&embeddings=ada"` | `"provider"` | `null` | `"ada"` | `null` |

## Agent.model Round-Trip Requirement

The `Agent.model` property returns a model string that can reconstruct an equivalent Agent:

```dart
final agent1 = Agent.forProvider(provider);
final modelString = agent1.model;

// Round-trip produces equivalent configuration
final agent2 = Agent(modelString);
assert(agent2.model == agent1.model);
```

The model string includes all model types (chat, embeddings, media) when the provider has defaults for them, ensuring the complete configuration is preserved.

## Implementation Notes

1. **Empty strings**: Empty model names (e.g., `chat=`) are treated as `null`
2. **Whitespace**: No automatic trimming - whitespace is preserved
3. **Case sensitivity**: Provider and model names are case-sensitive
4. **Special characters**: URI encoding is handled automatically for query parameters
5. **Round-trip support**: `Agent.model` always produces parseable strings

## Related Specifications

- [[Model-Configuration-Spec]] - Provider defaults, model resolution, and round-trip details
- [[Agent-Config-Spec]] - API key and environment configuration
