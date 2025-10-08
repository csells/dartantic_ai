This document defines the model string parsing system for dartantic 1.0, including the supported formats and parsing behavior.

## Overview

The `ModelStringParser` class extracts provider, chat model, and embeddings model names from a string input. It supports multiple formats for flexibility and backward compatibility.

## Supported Formats

| Format | Example | Parsed Output |
|--------|---------|---------------|
| **Provider Only** | `providerName` | provider: `providerName`, chat: `null`, embeddings: `null` |
| **Provider + Chat (colon)** | `providerName:chatModelName` | provider: `providerName`, chat: `chatModelName`, embeddings: `null` |
| **Provider + Chat (slash)** | `providerName/chatModelName` | provider: `providerName`, chat: `chatModelName`, embeddings: `null` |
| **Query Parameters** | `providerName?chat=chatModel&embeddings=embeddingsModel` | provider: `providerName`, chat: `chatModel`, embeddings: `embeddingsModel` |

## URI-Based Parsing

The parser leverages Dart's `Uri` class for robust parsing of various model string formats.

## String Building

The `toString()` method builds strings based on the components using URI formatting.

## Examples

### Basic Usage

```dart
// Provider only - uses all defaults
final parser1 = ModelStringParser.parse('openai');
// provider: 'openai', chat: null, embeddings: null

// Legacy format with chat model
final parser2 = ModelStringParser.parse('openai:gpt-4o');
// provider: 'openai', chat: 'gpt-4o', embeddings: null

// Slash format
final parser3 = ModelStringParser.parse('openai/gpt-4o');
// provider: 'openai', chat: 'gpt-4o', embeddings: null

// Query parameter format
final parser4 = ModelStringParser.parse('openai?chat=gpt-4o&embeddings=text-embedding-3-small');
// provider: 'openai', chat: 'gpt-4o', embeddings: 'text-embedding-3-small'
```

### Agent Integration

```dart
// Simple provider
final agent1 = Agent('openai');
// Uses default chat and embeddings models

// Specific chat model
final agent2 = Agent('openai:gpt-4o');
// Uses gpt-4o for chat, default for embeddings

// Different models for each operation
final agent3 = Agent('openai?chat=gpt-4o&embeddings=text-embedding-3-large');
// Explicit models for both operations
```

## Edge Cases

| Input | Provider | Chat Model | Embeddings Model |
|-------|----------|------------|------------------|
| `""` (empty) | Throws exception | - | - |
| `"provider:"` | `"provider"` | `null` | `null` |
| `"provider//"` | `"provider"` | `""` | `null` |
| `"provider?chat="` | `"provider"` | `null` | `null` |
| `"provider?chat=&embeddings=ada"` | `"provider"` | `null` | `"ada"` |

## Implementation Notes

1. **Empty strings**: Empty model names (e.g., `chat=`) are treated as `null`
2. **Whitespace**: No automatic trimming - whitespace is preserved
3. **Case sensitivity**: Provider and model names are case-sensitive
4. **Special characters**: URI encoding is handled automatically for query parameters
5. **Future extensibility**: The `other` query parameter supports future model types

## Related Specifications

- [[Model-Configuration-Spec]] - Provider defaults and model resolution
- [[Agent-Config-Spec]] - API key and environment configuration
