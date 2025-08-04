This guide shows the correct patterns for implementing providers and models in dartantic 1.0.

## Provider Implementation Pattern

```dart
class ExampleProvider extends Provider<ExampleChatOptions, ExampleEmbeddingsOptions> {
  static final Logger _logger = Logger('dartantic.chat.providers.example');

  /// Creates a provider instance with optional overrides.
  /// 
  /// API key resolution:
  /// - Constructor: Uses tryGetEnv() to allow lazy initialization without throwing
  /// - Model creation: Validates API key and throws if required but not found
  ExampleProvider({
    String? apiKey,
    Uri? baseUrl,
  }) : super(
          apiKey: apiKey ?? tryGetEnv('EXAMPLE_API_KEY'),
          baseUrl: baseUrl,
          name: 'example',
          displayName: 'Example AI',
          aliases: const ['ex', 'example-ai'],
          apiKeyName: 'EXAMPLE_API_KEY',  // null for local providers
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
            ProviderCaps.vision,
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
      baseUrl: baseUrl,  // Nullable, model knows default
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
      baseUrl: baseUrl,
      defaultOptions: options,  // Pass options directly
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    _logger.info('Fetching models from Example API');
    
    // Implementation to list available models
    // This is a simplified example - real implementations would make HTTP calls
    
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
}
```

## Chat Model Implementation Pattern

```dart
class ExampleChatModel extends ChatModel<ExampleChatOptions> {
  /// Creates a chat model instance.
  ExampleChatModel({
    required super.name,  // Always 'name', passed to super
    required this.apiKey,  // Non-null for cloud providers
    this.baseUrl,  // Nullable
    super.tools,
    super.temperature,
    super.defaultOptions,
  }) : _client = ExampleClient(
          apiKey: apiKey,
          baseUrl: baseUrl,  // Client knows its default
        );

  /// The API key (required for cloud providers).
  final String apiKey;

  /// Optional base URL override.
  final Uri? baseUrl;

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
    this.baseUrl,
    super.defaultOptions,
    super.dimensions,
    super.batchSize,
  }) : _client = ExampleClient(
          apiKey: apiKey,
          baseUrl: baseUrl,
        );

  final String apiKey;
  final Uri? baseUrl;
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

## Local Provider Pattern (No API Key)

```dart
class LocalProvider extends Provider<LocalChatOptions, EmbeddingsModelOptions> {
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
      ProviderCaps.vision,
    },
    baseUrl: null,
    apiKey: null,
  );

  static final Logger _logger = Logger('dartantic.chat.providers.local');

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
      baseUrl: baseUrl,
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
3. **Base URL**: Always nullable, models pass directly to client
4. **Options Handling**: Create new options objects with merged values from parameters and options
5. **Logging**: Include proper logging with `_logger.info()` calls
6. **Capabilities**: Accurately declare what your provider supports
7. **Error Handling**: Throw `Exception` for unsupported operations
8. **ModelInfo**: Include `displayName` and `description` when available

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
