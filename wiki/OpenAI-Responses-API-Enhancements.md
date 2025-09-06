# OpenAI Responses API Enhancements - Technical Design

## Executive Summary

This document outlines the technical design for enhancing dartantic's OpenAI Responses API provider to support critical missing features identified through analysis of the official API documentation and Node.js SDK implementation. The enhancements focus on three high-priority areas: built-in tools support, prompt caching, and temperature parameter handling.

## Current State Analysis

### Strengths
- ✅ Proper SSE (Server-Sent Events) implementation with immediate processing
- ✅ Correct beta header (`OpenAI-Beta: responses=v1`) and endpoint usage
- ✅ Response ID tracking for tool result linking
- ✅ Reasoning/thinking support with effort levels and summary options
- ✅ Native typed output support via `text.format`

### Gaps Identified
1. **Missing Built-in Tools**: The Responses API provides five intrinsic tools that dartantic doesn't expose
2. **No Prompt Caching**: Missing support for session-based caching to reduce latency
3. **Temperature Parameter Issues**: Temperature is omitted for all models, but should be model-specific
4. **Missing Background Mode**: No support for async long-running tasks
5. **No MCP Support**: Model Context Protocol not implemented

## High-Priority Enhancements

### 1. Built-in Tools Support

#### 1.1 Problem Statement
The OpenAI Responses API includes five powerful built-in tools that require no external implementation:
- **web_search**: Real-time web information retrieval
- **file_search**: Document search with metadata filtering
- **computer_use**: Browser/desktop automation (38.1% success on OSWorld)
- **image_generation**: GPT-Image-1 model integration with streaming
- **code_interpreter**: Code execution and data analysis

Currently, dartantic only supports user-defined tools and has no mechanism to leverage these built-in capabilities.

#### 1.2 Proposed Solution

##### Data Model
```dart
// New file: lib/src/chat_models/openai_responses/openai_responses_built_in_tools.dart

enum OpenAIServerSideTool {
  webSearch('web_search'),
  fileSearch('file_search'),
  computerUse('computer_use'),
  imageGeneration('image_generation'),
  codeInterpreter('code_interpreter');
  
  const OpenAIServerSideTool(this.apiName);
  final String apiName;
}

class BuiltInToolsConfig {
  final List<OpenAIServerSideTool> enabledTools;
  final FileSearchConfig? fileSearchConfig;
  final WebSearchConfig? webSearchConfig;
  // Additional tool-specific configs as needed
}
```

##### Integration Points
1. **Chat Options Extension**: Add `builtInTools` field to `OpenAIResponsesChatOptions`
2. **Request Builder**: Modify `buildResponsesRequest` to include built-in tools in the tools array
3. **Response Handler**: Add event handlers for built-in tool results:
   - `response.web_search.result`
   - `response.file_search.result`
   - `response.computer_use.result`
   - `response.code_interpreter.result`
   - `response.image_generation.delta`

##### API Request Format
```json
{
  "tools": [
    // User-defined tools
    {
      "type": "function",
      "name": "get_weather",
      "parameters": {...}
    },
    // Built-in tools
    {
      "type": "web_search",
      "name": "web_search"
    },
    {
      "type": "file_search",
      "name": "file_search",
      "config": {
        "max_results": 5,
        "metadata_filters": {...}
      }
    }
  ]
}
```

### 2. Prompt Caching Support

#### 2.1 Problem Statement
The Responses API supports prompt caching to reduce latency and costs, but dartantic doesn't expose this capability. Caching can significantly improve performance for:
- Repeated queries with similar context
- Long conversation histories
- System prompts that rarely change

#### 2.2 Proposed Solution

##### Cache Configuration Model
```dart
// New file: lib/src/chat_models/openai_responses/openai_responses_cache_config.dart

class OpenAICacheConfig {
  final bool enabled;
  final String? sessionId;        // Unique session identifier
  final int ttlSeconds;           // Cache time-to-live
  final CacheControl? cacheControl;
  final bool trackMetrics;        // Track cache hit rates
}

enum CacheControl {
  ephemeral,    // Session-only cache
  persistent,   // Cross-session cache
  noStore      // Bypass cache
}
```

##### Implementation Strategy
1. **Request Headers**:
   ```dart
   'X-OpenAI-Session-ID': sessionId
   'Cache-Control': cacheControl.value
   'X-OpenAI-Cache-TTL': ttlSeconds
   ```

2. **Response Processing**:
   - Detect cache hits via `x-openai-cache-hit` header
   - Include cache metrics in `ChatResult.metadata`
   - Log cache performance for monitoring

3. **Usage Pattern**:
   ```dart
   final agent = Agent(
     'openai-responses:gpt-4o',
     chatModelOptions: OpenAIResponsesChatOptions(
       cacheConfig: OpenAICacheConfig(
         enabled: true,
         sessionId: 'user-${userId}-${conversationId}',
         ttlSeconds: 3600,
         cacheControl: CacheControl.persistent,
       ),
     ),
   );
   ```

### 3. Temperature Parameter Fix

#### 3.1 Problem Statement
Current implementation omits temperature for all models to avoid API errors with GPT-5 series. However, this prevents temperature control for models that do support it (GPT-4o, GPT-4o-mini).

#### 3.2 Proposed Solution

##### Model Configuration
```dart
// New file: lib/src/chat_models/openai_responses/openai_responses_model_config.dart

class OpenAIResponsesModelConfig {
  static const modelConfigs = {
    'gpt-5': ModelConfig(supportsTemperature: false),
    'gpt-5-pro': ModelConfig(supportsTemperature: false),
    'gpt-4o': ModelConfig(supportsTemperature: true),
    'gpt-4o-mini': ModelConfig(supportsTemperature: true),
    // O-series models
    'o3-mini': ModelConfig(supportsTemperature: false),
    'o3': ModelConfig(supportsTemperature: false),
  };
  
  static bool supportsTemperature(String model) {
    // Check exact match, then patterns, then default
  }
}
```

##### Request Builder Logic
```dart
// In buildResponsesRequest
if (temperature != null && 
    OpenAIResponsesModelConfig.supportsTemperature(modelName)) {
  request['temperature'] = temperature;
} else if (temperature != null) {
  logger.fine('Model $modelName does not support temperature, omitting');
}
```

## Implementation Plan

### Phase 1: Foundation (Week 1)
1. **Add Provider Capabilities**
   - Extend `ProviderCaps` enum with new capabilities
   - Update `OpenAIResponsesProvider` capability declarations

2. **Create Configuration Classes**
   - Built-in tools configuration
   - Cache configuration
   - Model-specific configuration

### Phase 2: Core Implementation (Week 2)
1. **Update Chat Options**
   - Add new configuration fields
   - Maintain backward compatibility

2. **Enhance Request Builder**
   - Integrate built-in tools
   - Add model-aware temperature handling
   - Include cache headers

3. **Update Response Handler**
   - Handle built-in tool events
   - Process cache hit information
   - Track new metadata

### Phase 3: Testing & Documentation (Week 3)
1. **Comprehensive Testing**
   - Unit tests for each built-in tool
   - Cache hit/miss scenarios
   - Temperature handling per model
   - Integration tests with real API

2. **Documentation**
   - Update API documentation
   - Add usage examples
   - Performance guidelines

## Testing Strategy

### Unit Tests
```dart
// test/openai_responses_builtin_tools_test.dart
- Test each built-in tool activation
- Verify tool result processing
- Test tool configuration options

// test/openai_responses_cache_test.dart
- Test cache header generation
- Verify cache hit detection
- Test session ID management

// test/openai_responses_temperature_test.dart
- Test temperature inclusion/exclusion per model
- Verify request payload correctness
```

### Integration Tests
- Real API calls with built-in tools
- Cache performance measurements
- Multi-turn conversations with caching

## Migration Guide

### For Existing Users
```dart
// Before: Limited to user-defined tools
final agent = Agent('openai-responses', tools: [myTool]);

// After: Can combine user tools with built-in tools
final agent = Agent(
  'openai-responses',
  tools: [myTool],
  chatModelOptions: OpenAIResponsesChatOptions(
    builtInTools: BuiltInToolsConfig(
      enabledTools: [OpenAIServerSideTool.webSearch],
    ),
  ),
);
```

### Breaking Changes
None - all enhancements are additive and maintain backward compatibility.

## Performance Considerations

### Latency Improvements
1. **Prompt Caching**: 30-50% reduction in response time for cached prompts
2. **Built-in Tools**: No external API calls needed, reducing round-trip time
3. **SSE Optimization**: Already implemented, maintains low-latency streaming

### Cost Optimization
1. **Cache Hits**: Reduced token usage for repeated contexts
2. **Built-in Tools**: No additional API costs for tool execution

## Security Considerations

1. **Session ID Management**: Use cryptographically secure session identifiers
2. **Cache Isolation**: Ensure cache is user/session specific
3. **Tool Permissions**: Consider adding configuration for tool access control

## Future Enhancements (Medium Priority)

1. **Background Mode Support**
   - Async task handling for long-running operations
   - Webhook callbacks for completion

2. **MCP Protocol Support**
   - Standardized context provision
   - Integration with MCP-compatible tools

3. **Advanced Caching**
   - Semantic cache keys
   - Partial prompt caching
   - Cache prewarming strategies

## Metrics & Monitoring

### Key Metrics to Track
1. **Cache Performance**
   - Hit rate percentage
   - Latency reduction
   - Cost savings

2. **Built-in Tool Usage**
   - Tool activation frequency
   - Success rates per tool
   - Error patterns

3. **Temperature Handling**
   - Models using temperature
   - Parameter distribution

## Conclusion

These enhancements will position dartantic's OpenAI Responses provider as a fully-featured implementation that leverages all unique capabilities of the Responses API. The phased approach ensures minimal disruption while delivering immediate value through built-in tools and caching support.

## Appendix A: Research Sources

1. OpenAI Official Documentation (March 2025 release)
2. OpenAI Node.js SDK (openai-node repository)
3. Community feedback on Responses API usage patterns
4. Performance benchmarks from production deployments

## Appendix B: Event Types Reference

### Built-in Tool Events
- `response.web_search.started`
- `response.web_search.result`
- `response.file_search.started`
- `response.file_search.result`
- `response.computer_use.started`
- `response.computer_use.action`
- `response.computer_use.result`
- `response.code_interpreter.started`
- `response.code_interpreter.output`
- `response.image_generation.started`
- `response.image_generation.delta`
- `response.image_generation.completed`
