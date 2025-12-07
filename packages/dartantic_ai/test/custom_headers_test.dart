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
  group('Custom Headers Support', () {
    test('OpenAI provider passes custom headers to API calls', () async {
      await _testProviderHeaders('openai');
    });

    test('Google provider passes custom headers to API calls', () async {
      await _testProviderHeaders('google');
    });

    test('Anthropic provider passes custom headers to API calls', () async {
      await _testProviderHeaders('anthropic');
    });

    test('Mistral provider passes custom headers to API calls', () async {
      await _testProviderHeaders('mistral');
    });

    test('Ollama provider passes custom headers to API calls', () async {
      await _testProviderHeaders('ollama');
    });

    test('OpenAI Responses provider stores custom headers', () async {
      // OpenAI Responses uses openai_core SDK which wraps HTTP differently,
      // so we verify headers are stored on the provider instead
      const customHeaders = {'X-Custom-Header': 'test-value'};
      final provider = OpenAIResponsesProvider(
        apiKey: 'test-key',
        headers: customHeaders,
      );

      expect(
        provider.headers,
        containsPair('X-Custom-Header', 'test-value'),
        reason: 'OpenAI Responses provider should store custom headers',
      );
    });

    test('custom headers override internal headers', () async {
      // Test that custom headers can override internal headers
      // Using Google since it has a known internal header (x-goog-api-key)
      final captureClient = HeaderCapturingHttpClient();
      const customApiKey = 'custom-api-key-override';

      final provider = GoogleProvider(
        apiKey: 'original-api-key',
        headers: {'x-goog-api-key': customApiKey},
      );

      final model = GoogleChatModel(
        name: 'gemini-2.0-flash',
        apiKey: 'original-api-key',
        baseUrl: GoogleProvider.defaultBaseUrl,
        client: captureClient,
        headers: {'x-goog-api-key': customApiKey},
      );

      // Make request - it will fail but headers will be captured
      try {
        await model.sendStream([ChatMessage.user('test')]).drain<void>();
      } on Object {
        // Expected to fail with invalid API key, but headers captured
      }

      // Verify custom header overrides internal header
      expect(
        captureClient.lastRequestHeaders?['x-goog-api-key'],
        equals(customApiKey),
        reason: 'Custom header should override internal x-goog-api-key header',
      );

      // Verify provider has headers field accessible
      expect(provider.headers, containsPair('x-goog-api-key', customApiKey));
    });

    test('Provider headers field defaults to empty map', () {
      final provider = OpenAIProvider(apiKey: 'test-key');
      expect(provider.headers, isEmpty);
    });
  });
}

Future<void> _testProviderHeaders(String providerName) async {
  final captureClient = HeaderCapturingHttpClient();
  const customHeader = 'X-Custom-Test-Header';
  const customValue = 'test-value-12345';

  // Get the base provider for API key
  final baseProvider = Providers.get(providerName);

  // Create provider with custom headers
  final customHeaders = {customHeader: customValue};

  Provider provider;
  ChatModel model;

  switch (providerName) {
    case 'openai':
      provider = OpenAIProvider(
        apiKey: baseProvider.apiKey,
        headers: customHeaders,
      );
      model = OpenAIChatModel(
        name: 'gpt-4o-mini',
        apiKey: baseProvider.apiKey,
        client: captureClient,
        headers: customHeaders,
        defaultOptions: const OpenAIChatOptions(),
      );
    case 'google':
      provider = GoogleProvider(
        apiKey: baseProvider.apiKey,
        headers: customHeaders,
      );
      model = GoogleChatModel(
        name: 'gemini-2.0-flash',
        apiKey: baseProvider.apiKey!,
        baseUrl: GoogleProvider.defaultBaseUrl,
        client: captureClient,
        headers: customHeaders,
        defaultOptions: const GoogleChatModelOptions(),
      );
    case 'anthropic':
      provider = AnthropicProvider(
        apiKey: baseProvider.apiKey,
        headers: customHeaders,
      );
      model = AnthropicChatModel(
        name: 'claude-sonnet-4-20250514',
        apiKey: baseProvider.apiKey!,
        client: captureClient,
        headers: customHeaders,
        defaultOptions: const AnthropicChatOptions(),
      );
    case 'mistral':
      provider = MistralProvider(
        apiKey: baseProvider.apiKey,
        headers: customHeaders,
      );
      model = MistralChatModel(
        name: 'open-mistral-7b',
        apiKey: baseProvider.apiKey!,
        client: captureClient,
        headers: customHeaders,
        defaultOptions: const MistralChatModelOptions(),
      );
    case 'ollama':
      provider = OllamaProvider(headers: customHeaders);
      model = OllamaChatModel(
        name: 'qwen2.5:7b-instruct',
        baseUrl: OllamaProvider.defaultBaseUrl,
        client: captureClient,
        headers: customHeaders,
        defaultOptions: const OllamaChatOptions(),
      );
    default:
      throw ArgumentError('Unknown provider: $providerName');
  }

  // Verify provider has headers
  expect(
    provider.headers,
    containsPair(customHeader, customValue),
    reason: '$providerName provider should store custom headers',
  );

  // Make a request to capture headers
  try {
    await model.sendStream([ChatMessage.user('Say "hi"')]).drain<void>();
  } on Object {
    // Request may fail for various reasons (Ollama not running, etc.)
    // but we still capture headers from the attempt
  }

  // Verify headers were passed to the HTTP request
  expect(
    captureClient.lastRequestHeaders,
    isNotNull,
    reason: '$providerName should have made an HTTP request',
  );
  expect(
    captureClient.lastRequestHeaders,
    containsPair(customHeader, customValue),
    reason: '$providerName should pass custom headers to HTTP requests',
  );
}

/// HTTP client that captures headers from requests
class HeaderCapturingHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  Map<String, String>? lastRequestHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequestHeaders = Map<String, String>.from(request.headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
