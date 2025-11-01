This guide shows the correct patterns for implementing providers and models in dartantic 1.0.

## Critical Patterns Summary

**Every provider MUST:**
1. Have a private static final logger: `static final Logger _logger = ...`
2. Define a public defaultBaseUrl: `static final defaultBaseUrl = Uri.parse('...')`
3. Use `super.baseUrl` in constructor (not `baseUrl: baseUrl`)
4. Pass `baseUrl ?? defaultBaseUrl` to models in create methods
5. Models should accept required `Uri baseUrl` from provider
6. Implement `createMediaModel` (or throw `UnsupportedError`) when
   advertising `ProviderCaps.mediaGeneration`

## Provider Implementation Pattern

```dart
class ExampleProvider extends Provider<
  ExampleChatOptions,
  ExampleEmbeddingsOptions,
  ExampleMediaOptions
> {
  // IMPORTANT: Logger must be private (_logger not log) and static final
  static final Logger _logger = Logger('dartantic.chat.providers.example');

  /// Default base URL for the Example API.
  /// IMPORTANT: All providers must have a public defaultBaseUrl constant
  static final defaultBaseUrl = Uri.parse('https://api.example.com/v1');

  /// Environment variable name for API key
  static const defaultApiKeyName = 'EXAMPLE_API_KEY';

  /// Creates a provider instance with optional overrides.
  ///
  /// API key resolution:
  /// - Constructor: Uses tryGetEnv() to allow lazy initialization without throwing
  /// - Model creation: Validates API key and throws if required but not found
  ExampleProvider({
    String? apiKey,
    super.baseUrl,  // Use super.baseUrl, don't provide defaults here
  }) : super(
          apiKey: apiKey ?? tryGetEnv(defaultApiKeyName),
          name: 'example',
          displayName: 'Example AI',
          aliases: const ['ex', 'example-ai'],
          apiKeyName: defaultApiKeyName,  // null for local providers
          defaultModelNames: const {
            ModelKind.chat: 'example-chat-v1',
            ModelKind.embeddings: 'example-embed-v1',
          },
          caps: const {
            ProviderCaps.chat,
            ProviderCaps.embeddings,
            ProviderCaps.streaming,
            ProviderCaps.tools,
            ProviderCaps.multiToolCalls,
            ProviderCaps.typedOutput,
            ProviderCaps.chatVision,
          },
        );

  @override
  ChatModel createChatModel({
    String? name,  // Note: 'name' not 'modelName'
    List<Tool>? tools,
    double? temperature,
    ExampleChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating Example model: $modelName with '
      '${tools?.length ?? 0} tools, '
      'temperature: $temperature',
    );

    // Validate API key at model creation time
    if (apiKey == null) {
      throw ArgumentError('EXAMPLE_API_KEY is required for Example provider');
    }

    return ExampleChatModel(
      name: modelName,  // Pass as 'name'
      apiKey: apiKey,  // Now validated to be non-null
      baseUrl: baseUrl ?? defaultBaseUrl,  // IMPORTANT: Pass baseUrl with fallback
      tools: tools,
      temperature: temperature,
      defaultOptions: ExampleChatOptions(
        temperature: temperature ?? options?.temperature,
        topP: options?.topP,
        maxTokens: options?.maxTokens,
        // Add other options as needed
      ),
    );
  }

  @override
  EmbeddingsModel createEmbeddingsModel({
    String? name,
    ExampleEmbeddingsOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;

    _logger.info(
      'Creating Example embeddings model: $modelName with '
      'options: $options',
    );

    // Validate API key at model creation time
    if (apiKey == null) {
      throw ArgumentError('EXAMPLE_API_KEY is required for Example provider');
    }

    return ExampleEmbeddingsModel(
      name: modelName,
      apiKey: apiKey,  // Now validated to be non-null
      baseUrl: baseUrl ?? defaultBaseUrl,  // Use provider's default
      defaultOptions: options,  // Pass options directly
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    // Use defaultBaseUrl when baseUrl is null
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'models');

    _logger.info('Fetching models from Example API: $url');

    // Implementation to list available models
    // Real implementations would make HTTP calls with the resolved URL
    
    yield ModelInfo(
      name: 'example-chat-v1',
      providerName: name,
      kinds: {ModelKind.chat},
      displayName: 'Example Chat Model v1',
      description: 'A chat model for text generation',
    );
    yield ModelInfo(
      name: 'example-embed-v1',
      providerName: name,
      kinds: {ModelKind.embeddings},
      displayName: 'Example Embeddings Model v1',
      description: 'A model for text embeddings',
    );
  }

  @override
  MediaGenerationModel<ExampleMediaOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    ExampleMediaOptions? options,
  }) {
    if (!caps.contains(ProviderCaps.mediaGeneration)) {
      throw UnsupportedError('Media generation is not supported');
    }

    final modelName = name ?? defaultModelNames[ModelKind.media]!;
    return ExampleMediaModel(
      name: modelName,
      tools: tools,
      defaultOptions: options ?? const ExampleMediaOptions(),
    );
  }
}
```

## Chat Model Implementation Pattern

```dart
class ExampleChatModel extends ChatModel<ExampleChatOptions> {
  /// Creates a chat model instance.
  ExampleChatModel({
    required super.name,  // Always 'name', passed to super
    required this.apiKey,  // Non-null for cloud providers
    required this.baseUrl,  // Required from provider (already has fallback)
    super.tools,
    super.temperature,
    super.defaultOptions,
  }) : _client = ExampleClient(
          apiKey: apiKey,
          // How to pass baseUrl depends on client library:
          // If client accepts nullable String:
          baseUrl: baseUrl.toString(),
          // If client requires non-nullable String and you need different default:
          // baseUrl: baseUrl.toString() ?? 'https://api.example.com/v1',
        );

  /// The API key (required for cloud providers).
  final String apiKey;

  /// Base URL for API requests (provider supplies with fallback).
  final Uri baseUrl;

  final ExampleClient _client;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    ExampleChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    // Process messages
    final processedMessages = messages;
    
    // Stream implementation
    await for (final chunk in _client.stream(...)) {
      yield ChatResult<ChatMessage>(
        // ... result construction
      );
    }
  }

  @override
  void dispose() {
    _client.close();
  }
}
```

## Embeddings Model Implementation Pattern

```dart
class ExampleEmbeddingsModel extends EmbeddingsModel<ExampleEmbeddingsOptions> {
  /// Creates an embeddings model instance.
  ExampleEmbeddingsModel({
    required super.name,  // Always 'name'
    required this.apiKey,
    required this.baseUrl,  // Required from provider
    super.defaultOptions,
    super.dimensions,
    super.batchSize,
  }) : _client = ExampleClient(
          apiKey: apiKey,
          baseUrl: baseUrl.toString(),
        );

  final String apiKey;
  final Uri baseUrl;
  final ExampleClient _client;

  @override
  Future<EmbeddingsResult> embedQuery(
    String query, {
    ExampleEmbeddingsOptions? options,
  }) async {
    final response = await _client.embed(
      texts: [query],
      model: name,
      dimensions: options?.dimensions ?? dimensions,
    );
    
    return EmbeddingsResult(
      embedding: response.embeddings.first,
      usage: LanguageModelUsage(
        inputTokens: response.usage?.inputTokens,
        outputTokens: response.usage?.outputTokens,
      ),
    );
  }

  @override
  Future<BatchEmbeddingsResult> embedDocuments(
    List<String> texts, {
    ExampleEmbeddingsOptions? options,
  }) async {
    final response = await _client.embed(
      texts: texts,
      model: name,
      dimensions: options?.dimensions ?? dimensions,
    );
    
    return BatchEmbeddingsResult(
      embeddings: response.embeddings,
      usage: LanguageModelUsage(
        inputTokens: response.usage?.inputTokens,
        outputTokens: response.usage?.outputTokens,
      ),
    );
  }

  @override
  void dispose() {
    _client.close();
  }
}
```

## Local Provider Pattern (No API Key or Base URL)

```dart
class LocalProvider extends Provider<LocalChatOptions, EmbeddingsModelOptions> {
  // Logger must still be private and static final
  static final Logger _logger = Logger('dartantic.chat.providers.local');

  // Local providers typically connect to localhost, so may have a default
  // But some may not need any URL at all
  static final defaultBaseUrl = Uri.parse('http://localhost:11434/api');

  LocalProvider() : super(
    name: 'local',
    displayName: 'Local Model',
    aliases: const [],
    apiKeyName: null,  // No API key needed
    defaultModelNames: const {
      ModelKind.chat: 'llama3.2',
    },
    caps: const {
      ProviderCaps.chat,
      ProviderCaps.streaming,
      ProviderCaps.multiToolCalls,
      ProviderCaps.typedOutput,
      ProviderCaps.chatVision,
    },
    baseUrl: null,  // No base URL override in constructor
    apiKey: null,
  );

  @override
  ChatModel createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    LocalChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating Local model: $modelName with '
      '${tools?.length ?? 0} tools, '
      'temp: $temperature',
    );

    return LocalChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      baseUrl: baseUrl ?? defaultBaseUrl,  // Even local providers should follow pattern
      defaultOptions: LocalChatOptions(
        temperature: temperature ?? options?.temperature,
        // Add other options as needed
      ),
    );
  }

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw Exception('Local provider does not support embeddings models');
}
```



## Static Provider Registration

Add your provider to the Provider class:

```dart
abstract class Provider {
  // ... base class definition ...
  
  // Add your provider as a static instance
  static final example = ExampleProvider();
  
  // Include in the all providers list
  static final all = <Provider>[
    openai,
    google,
    anthropic,
    cohere,
    mistral,
    ollama,
    example,  // Add your provider here
  ];
}
```

## Key Implementation Rules

1. **Parameter Naming**: Always use `name` for model names, not `model`, `modelId`, or `modelName`
2. **API Key Handling**:
   - Cloud providers: use `tryGetEnv()` in constructor (allows lazy initialization)
   - Model creation: validate API key and throw if required but not found
   - Local providers: no API key parameter at all
3. **Base URL Management**:
   - Provider: Define public `static final defaultBaseUrl = Uri.parse('...')`
   - Constructor: Use `super.baseUrl` parameter (no defaults)
   - Model creation: Pass `baseUrl ?? defaultBaseUrl` to models
   - Models: Accept required `Uri baseUrl` from provider
4. **Options Handling**: Create new options objects with merged values from parameters and options
5. **Logger Convention**:
   - MUST be private: `static final Logger _logger = ...` (not `log` or public)
   - Place immediately after class declaration
   - Use hierarchical naming: `Logger('dartantic.chat.providers.example')`
   - Log lifecycle milestones at INFO, detailed events at FINE
6. **Capabilities**: Accurately declare what your provider supports
7. **Error Handling**:
   - Follow exception transparency: no try-catch blocks that suppress errors
   - Let exceptions bubble up for diagnosis
   - Only wrap provider-specific exceptions at boundaries
8. **ModelInfo**: Include `displayName` and `description` when available
9. **HTTP Client**: Wrap HTTP clients with `RetryHttpClient` for automatic retry on transient failures
10. **Message History**: Must pass `validateMessageHistory()` utility
    - System messages only at index 0
    - Strict user/model/user/model alternation thereafter
11. **Metadata**: All metadata values must be JSON-serializable (String, num, bool, List, Map, null)
12. **Tool ID Coordination**: Use `tool_id_helpers.dart` for providers that don't supply tool IDs

## Special Cases

### Different API Endpoints

If your provider needs different endpoints for different operations (e.g., OpenAI Responses):

```dart
class SpecialProvider extends Provider<...> {
  // Primary endpoint (e.g., for chat)
  static final defaultBaseUrl = Uri.parse('https://api.example.com/v1/special');

  // Secondary endpoint (e.g., for embeddings or model listing)
  static final _standardApiUrl = Uri.parse('https://api.example.com/v1');

  @override
  ChatModel createChatModel(...) {
    // Uses special endpoint
    return SpecialChatModel(
      baseUrl: baseUrl ?? defaultBaseUrl,
      ...
    );
  }

  @override
  EmbeddingsModel createEmbeddingsModel(...) {
    // Uses standard endpoint
    return SpecialEmbeddingsModel(
      baseUrl: baseUrl ?? _standardApiUrl,
      ...
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    // Uses standard endpoint for listing
    final resolvedBaseUrl = baseUrl ?? _standardApiUrl;
    ...
  }
}
```

### Client Library Requirements

Different HTTP client libraries have different requirements:

```dart
// If client accepts nullable String:
ExampleClient(
  baseUrl: baseUrl?.toString(),
)

// If client requires non-nullable String:
OpenAIClient(
  baseUrl: baseUrl.toString() ?? 'https://default.url',
)
```

## Testing Your Provider

```dart
// Test provider discovery
final provider = Providers.get('example');
assert(provider.name == 'example');

// Test model creation
final chatModel = provider.createChatModel();
final embeddingsModel = provider.createEmbeddingsModel();

// Test model listing
await for (final model in provider.listModels()) {
  print('${model.name} supports ${model.kinds}');
}

// Test Agent integration
final agent = Agent('example');
final result = await agent.send('Hello');

// Test embeddings
final embed = await agent.embedQuery('test');
```

## Custom Orchestrators for Provider Limitations

Some providers have API limitations that require custom orchestration logic. The `ChatOrchestratorProvider` interface allows providers to supply their own orchestrators based on the request context.

### When to Use Custom Orchestrators

Use a custom orchestrator when:
1. **API Limitations**: Provider doesn't support certain combinations of features (e.g., tools + typed output)
2. **Special Workflows**: Provider requires multi-step workflows for certain capabilities
3. **Optimization**: Provider-specific patterns can be optimized for better performance

### Implementing ChatOrchestratorProvider

```dart
import 'package:json_schema/json_schema.dart';
import '../agent/orchestrators/streaming_orchestrator.dart';
import '../agent/orchestrators/default_streaming_orchestrator.dart';
import 'chat_orchestrator_provider.dart';

class GoogleProvider extends Provider<GoogleChatModelOptions, GoogleEmbeddingsModelOptions>
    implements ChatOrchestratorProvider {
  // ... existing provider code ...

  @override
  (StreamingOrchestrator, List<Tool>?) getChatOrchestratorAndTools({
    required JsonSchema? outputSchema,
    required List<Tool>? tools,
  }) {
    final hasTools = tools != null && tools.isNotEmpty;

    if (outputSchema != null && hasTools) {
      // Use custom orchestrator for tools + typed output
      // Note: Not const because orchestrator has mutable state
      return (GoogleDoubleAgentOrchestrator(), tools);
    }

    // Standard cases use default orchestrator
    return (const DefaultStreamingOrchestrator(), tools);
  }
}
```

### Example: Google Double Agent Pattern

Google's API doesn't support using tools and `outputSchema` simultaneously. The `GoogleDoubleAgentOrchestrator` works around this with a two-phase approach:

**Phase 1 - Tool Execution:**
- Send request with tools (no outputSchema)
- Suppress text output (only care about tool calls)
- Execute all tool calls
- Accumulate tool results

**Phase 2 - Structured Output:**
- Send tool results with outputSchema (no tools)
- Return structured JSON output
- Attach metadata about suppressed content from Phase 1

```dart
class GoogleDoubleAgentOrchestrator extends DefaultStreamingOrchestrator {
  // Instance state is safe - each request gets new orchestrator instance
  bool _isPhase1 = true;

  @override
  String get providerHint => 'google-double-agent';

  @override
  void initialize(StreamingState state) {
    super.initialize(state);
    _isPhase1 = true;
  }

  @override
  Stream<StreamingIterationResult> processIteration(
    ChatModel<ChatModelOptions> model,
    StreamingState state, {
    JsonSchema? outputSchema,
  }) async* {
    if (_isPhase1) {
      // Phase 1: Execute tools
      yield* _executePhase1(model, state);

      // Transition to Phase 2
      if (!_isPhase1) {
        yield* processIteration(model, state, outputSchema: outputSchema);
      }
    } else {
      // Phase 2: Get structured output
      yield* _executePhase2(model, state, outputSchema);
    }
  }

  @override
  bool allowTextStreaming(
    StreamingState state,
    ChatResult<ChatMessage> result,
  ) => !_isPhase1; // Only stream text in Phase 2
}
```

### Model Behavior Changes

When implementing a double agent pattern, the model's `sendStream()` method needs to conditionally exclude tools when `outputSchema` is present:

```dart
@override
Stream<ChatResult<ChatMessage>> sendStream(
  List<ChatMessage> messages, {
  GoogleChatModelOptions? options,
  JsonSchema? outputSchema,
}) {
  final request = _buildRequest(
    messages,
    options: options,
    outputSchema: outputSchema,
  );

  // ... streaming implementation
}

gl.GenerateContentRequest _buildRequest(
  List<ChatMessage> messages, {
  GoogleChatModelOptions? options,
  JsonSchema? outputSchema,
}) {
  // Google doesn't support tools + outputSchema simultaneously.
  // When outputSchema is provided, exclude tools (double agent phase 2).
  final toolsToSend = outputSchema != null
      ? const <Tool>[]
      : (tools ?? const <Tool>[]);

  return gl.GenerateContentRequest(
    model: normalizedModel,
    systemInstruction: _extractSystemInstruction(messages),
    contents: contents,
    generationConfig: generationConfig,
    tools: toolsToSend.toToolList(
      enableCodeExecution: enableCodeExecution,
    ),
  );
}
```

### Key Implementation Notes

1. **Instance State**: Custom orchestrators can have mutable instance variables because each request gets a new orchestrator instance
2. **Metadata Preservation**: Use `StreamingState.addSuppressedTextParts()` and `addSuppressedMetadata()` to track suppressed content
3. **Tool Result Consolidation**: Phase 1 executes tools and adds results to history before Phase 2
4. **Text Suppression**: Override `allowTextStreaming()` to control when text is streamed to the user
5. **Clean Separation**: The orchestrator handles workflow logic; the model handles API communication

### Provider Capabilities

When implementing a double agent pattern, declare the appropriate capability:

```dart
caps: {
  ProviderCaps.chat,
  ProviderCaps.tools,
  ProviderCaps.typedOutput,
  ProviderCaps.typedOutputWithTools, // Declare this capability
},
```

This ensures the provider is included in tests that verify tools + typed output functionality.
