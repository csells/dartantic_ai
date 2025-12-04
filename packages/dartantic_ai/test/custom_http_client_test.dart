/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('Custom HTTP Client Support', () {
    test('OpenAI provider uses custom HTTP client', () async {
      await _testProviderHttpClient('openai');
    });

    test('Google provider uses custom HTTP client', () async {
      await _testProviderHttpClient('google');
    });

    test('Anthropic provider uses custom HTTP client', () async {
      await _testProviderHttpClient('anthropic');
    });

    test('Mistral provider uses custom HTTP client', () async {
      await _testProviderHttpClient('mistral');
    });

    test('Ollama provider uses custom HTTP client', () async {
      await _testProviderHttpClient('ollama');
    });
  });
}

Future<void> _testProviderHttpClient(String providerName) async {
  final trackingClient = TrackingHttpClient();

  // Get the base provider
  final baseProvider = Providers.get(providerName);

  // Create a custom provider with tracking HTTP client
  Provider customProvider;
  switch (providerName) {
    case 'openai':
      customProvider = CustomOpenAIProvider(
        apiKey: baseProvider.apiKey,
        client: trackingClient,
      );
    case 'google':
      customProvider = CustomGoogleProvider(
        apiKey: baseProvider.apiKey,
        client: trackingClient,
      );
    case 'anthropic':
      customProvider = CustomAnthropicProvider(
        apiKey: baseProvider.apiKey,
        client: trackingClient,
      );
    case 'mistral':
      customProvider = CustomMistralProvider(
        apiKey: baseProvider.apiKey,
        client: trackingClient,
      );
    case 'ollama':
      customProvider = CustomOllamaProvider(client: trackingClient);
    default:
      throw ArgumentError('Unknown provider: $providerName');
  }

  // Create agent and make a real API call
  final agent = Agent.forProvider(customProvider);
  await agent.send('Say "hi"');

  // Verify the custom client was used
  expect(
    trackingClient.requestCount,
    greaterThan(0),
    reason: '$providerName should use custom HTTP client',
  );
}

/// HTTP client that tracks requests without modifying them
class TrackingHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

// Custom provider implementations that accept HTTP clients

class CustomOpenAIProvider extends OpenAIProvider {
  CustomOpenAIProvider({required super.apiKey, required this.client});

  final http.Client client;

  @override
  ChatModel<OpenAIChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    OpenAIChatOptions? options,
  }) => OpenAIChatModel(
    name: name ?? defaultModelNames[ModelKind.chat]!,
    apiKey: apiKey,
    client: client,
    tools: tools,
    temperature: temperature,
    defaultOptions: options ?? const OpenAIChatOptions(),
  );
}

class CustomGoogleProvider extends GoogleProvider {
  CustomGoogleProvider({required super.apiKey, required this.client});

  final http.Client client;

  @override
  ChatModel<GoogleChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    GoogleChatModelOptions? options,
  }) => GoogleChatModel(
    name: name ?? defaultModelNames[ModelKind.chat]!,
    apiKey: apiKey!,
    baseUrl: baseUrl ?? GoogleProvider.defaultBaseUrl,
    client: client,
    tools: tools,
    temperature: temperature,
    enableThinking: enableThinking,
    defaultOptions: options ?? const GoogleChatModelOptions(),
  );
}

class CustomAnthropicProvider extends AnthropicProvider {
  CustomAnthropicProvider({required super.apiKey, required this.client});

  final http.Client client;

  @override
  ChatModel<AnthropicChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    AnthropicChatOptions? options,
  }) => AnthropicChatModel(
    name: name ?? defaultModelNames[ModelKind.chat]!,
    apiKey: apiKey!,
    client: client,
    tools: tools,
    temperature: temperature,
    enableThinking: enableThinking,
    defaultOptions: options ?? const AnthropicChatOptions(),
  );
}

class CustomMistralProvider extends MistralProvider {
  CustomMistralProvider({required super.apiKey, required this.client});

  final http.Client client;

  @override
  ChatModel<MistralChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    MistralChatModelOptions? options,
  }) => MistralChatModel(
    name: name ?? defaultModelNames[ModelKind.chat]!,
    apiKey: apiKey!,
    client: client,
    tools: tools,
    temperature: temperature,
    defaultOptions: options ?? const MistralChatModelOptions(),
  );
}

class CustomOllamaProvider extends OllamaProvider {
  CustomOllamaProvider({required this.client});

  final http.Client client;

  @override
  ChatModel<OllamaChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    OllamaChatOptions? options,
  }) => OllamaChatModel(
    name: name ?? defaultModelNames[ModelKind.chat]!,
    baseUrl: baseUrl,
    client: client,
    tools: tools,
    temperature: temperature,
    defaultOptions: options ?? const OllamaChatOptions(),
  );
}
