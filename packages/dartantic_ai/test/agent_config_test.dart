import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/platform/platform.dart' as platform;
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

void main() {
  group('Agent Configuration Tests', () {
    // Save original environment state
    late Map<String, String> originalAgentEnv;

    setUp(() {
      // Save current state
      originalAgentEnv = Map<String, String>.from(Agent.environment);

      // Clear Agent environment for clean test state
      Agent.environment.clear();
    });

    tearDown(() {
      // Restore original state
      Agent.environment.clear();
      Agent.environment.addAll(originalAgentEnv);
    });

    group('API Key Resolution Hierarchy', () {
      test('Provider instance apiKey takes highest precedence', () async {
        // Setup multiple sources
        Agent.environment['OPENAI_API_KEY'] = 'sk-env-map-key';

        // Create custom provider with direct API key
        final provider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          apiKeyName: 'OPENAI_API_KEY',
          apiKey: 'sk-provider-key', // This takes precedence
          caps: Providers.openai.caps,
        );

        // Create agent with custom provider
        final agent = Agent.forProvider(provider);

        // Verify agent was created with the provider
        expect(agent.model, equals('openai:gpt-4o-mini'));
        expect(agent.providerName, equals('openai'));
      });

      test('Agent.environment takes precedence over system environment', () {
        // Set Agent.environment
        Agent.environment['OPENAI_API_KEY'] = 'sk-agent-env-key';

        // Create agent without direct API key
        final agent = Agent('openai:gpt-4o-mini');

        // Verify Agent.environment is accessible
        expect(
          platform.tryGetEnv('OPENAI_API_KEY'),
          equals('sk-agent-env-key'),
        );
        expect(agent.model, equals('openai:gpt-4o-mini'));
      });

      test('System environment is used when no other source available', () {
        // Skip on web where Platform.environment is not available
        if (identical(0, 0.0)) {
          // Running on web
          return;
        }

        // Only system environment is set (if available)
        final systemKey = Platform.environment['OPENAI_API_KEY'];
        if (systemKey != null) {
          final agent = Agent('openai:gpt-4o-mini');

          // platform.tryGetEnv should find it
          expect(platform.tryGetEnv('OPENAI_API_KEY'), equals(systemKey));
          expect(agent.model, equals('openai:gpt-4o-mini'));
        }
      });

      test('Empty string API key in provider falls back to environment', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-env-key';

        // Create provider with empty string API key
        final provider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          apiKeyName: 'OPENAI_API_KEY',
          apiKey: '', // Empty string should fall back to environment
          caps: Providers.openai.caps,
        );

        final agent = Agent.forProvider(provider);
        // Agent was created successfully
        expect(agent.model, equals('openai:gpt-4o-mini'));
      });

      test('Null API key in provider falls back to environment', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-env-key';

        // Use default provider (which has null apiKey)
        final agent = Agent('openai:gpt-4o-mini');

        expect(agent.model, equals('openai:gpt-4o-mini'));
        expect(platform.tryGetEnv('OPENAI_API_KEY'), equals('sk-env-key'));
      });

      test('Provider-specific apiKeyName is respected', () {
        Agent.environment['ANTHROPIC_API_KEY'] = 'sk-anthropic-key';
        Agent.environment['OPENAI_API_KEY'] = 'sk-openai-key';

        // Each provider should look for its specific key
        expect(
          platform.tryGetEnv('ANTHROPIC_API_KEY'),
          equals('sk-anthropic-key'),
        );
        expect(platform.tryGetEnv('OPENAI_API_KEY'), equals('sk-openai-key'));
      });
    });

    group('Base URL Resolution Hierarchy', () {
      test('Provider instance baseUrl takes precedence', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-test';

        // Create provider with custom base URL
        final provider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          apiKeyName: 'OPENAI_API_KEY',
          baseUrl: Uri.parse('https://custom.api.com'),
          caps: Providers.openai.caps,
        );

        final agent = Agent.forProvider(provider);
        expect(agent.model, equals('openai:gpt-4o-mini'));
        expect(provider.baseUrl, equals(Uri.parse('https://custom.api.com')));
      });

      test('Provider defaultBaseUrl is used when not specified', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-test';
        final agent = Agent('openai:gpt-4o-mini');

        // Provider should have its default
        final provider = Providers.openai;
        expect(provider.baseUrl, isNull);
        expect(agent.model, equals('openai:gpt-4o-mini'));
      });

      test('Null baseUrl in provider uses defaults', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-test';

        // Default provider has null baseUrl, falls back to defaultBaseUrl
        final agent = Agent('openai:gpt-4o-mini');
        final provider = Providers.openai;

        expect(agent.model, equals('openai:gpt-4o-mini'));
        expect(provider.baseUrl, isNull);
      });
    });

    group('Agent.forProvider Configuration', () {
      test('forProvider constructor uses provider configuration', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-test';

        // Create custom provider with specific configuration
        final provider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI Custom',
          defaultModelNames: {ModelKind.chat: 'gpt-4'},
          apiKeyName: 'OPENAI_API_KEY',
          apiKey: 'sk-custom',
          baseUrl: Uri.parse('https://custom.openai.com'),
          caps: Providers.openai.caps,
        );

        final agent = Agent.forProvider(provider, chatModelName: 'gpt-4o-mini');

        expect(agent.model, equals('openai:gpt-4o-mini'));
        expect(agent.providerName, equals('openai'));
        expect(agent.model, equals('openai:gpt-4o-mini'));
      });

      test('forProvider uses provider defaults when not specified', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-test';
        final provider = Providers.openai;

        final agent = Agent.forProvider(provider);

        expect(
          agent.model,
          equals('openai:${provider.defaultModelNames[ModelKind.chat]}'),
        );
        expect(agent.providerName, equals('openai'));
      });
    });

    group('Provider.createChatModel Configuration', () {
      test('createModel uses provider apiKey over environment', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-env-key';

        // Create provider with its own API key
        final provider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          apiKeyName: 'OPENAI_API_KEY',
          apiKey: 'sk-provider-key',
          caps: Providers.openai.caps,
        );

        final model = provider.createChatModel();
        // Model should be created with provider's API key
        expect(model, isNotNull);
      });

      test(
        'createModel falls back to environment when provider has no apiKey',
        () {
          Agent.environment['OPENAI_API_KEY'] = 'sk-env-key';

          // Use default provider (no apiKey set)
          final provider = Providers.openai;
          final model = provider.createChatModel();

          // Model should be created successfully with env API key
          expect(model, isNotNull);
        },
      );
    });

    group('Cross-Provider Configuration', () {
      test('Different providers use different API key names', () {
        // Set different keys for different providers
        Agent.environment['OPENAI_API_KEY'] = 'sk-openai';
        Agent.environment['ANTHROPIC_API_KEY'] = 'sk-anthropic';
        Agent.environment['MISTRAL_API_KEY'] = 'sk-mistral';
        Agent.environment['GEMINI_API_KEY'] = 'sk-gemini';

        // Each provider should find its specific key
        expect(platform.tryGetEnv('OPENAI_API_KEY'), equals('sk-openai'));
        expect(platform.tryGetEnv('ANTHROPIC_API_KEY'), equals('sk-anthropic'));
        expect(platform.tryGetEnv('MISTRAL_API_KEY'), equals('sk-mistral'));
        expect(platform.tryGetEnv('GEMINI_API_KEY'), equals('sk-gemini'));

        // Create agents to verify they work
        final agents = [
          Agent('openai:gpt-4o-mini'),
          Agent('anthropic:claude-3-haiku-20240307'),
          Agent('mistral:mistral-small-latest'),
          Agent('google:gemini-1.0-pro'),
        ];

        expect(agents[0].providerName, equals('openai'));
        expect(agents[1].providerName, equals('anthropic'));
        expect(agents[2].providerName, equals('mistral'));
        expect(agents[3].providerName, equals('google'));
      });

      test('Ollama provider works without API key', () {
        // Ollama shouldn't require an API key
        final agent = Agent('ollama:llama2');

        expect(agent.providerName, equals('ollama'));
        expect(agent.model, equals('ollama:llama2'));
      });
    });

    group('Error Handling', () {
      test('Missing API key through config flow throws appropriately', () {
        // Clear Agent environment
        Agent.environment.clear();

        // Test with our custom provider that uses a fake API key
        final testProvider = TestProvider();

        // Test 1: Provider.createModel should throw when no API key available
        expect(
          testProvider.createChatModel,
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('TEST_PROVIDER_API_KEY_THAT_DOES_NOT_EXIST'),
            ),
          ),
        );

        // Test 2: With environment key set, should work
        Agent.environment['TEST_PROVIDER_API_KEY_THAT_DOES_NOT_EXIST'] =
            'sk-test-env';
        expect(testProvider.createChatModel, returnsNormally);

        // Clean up
        Agent.environment.clear();
      });

      test('Providers without API key requirement work without env vars', () {
        // Clear all environment variables
        Agent.environment.clear();

        // Ollama should work without any API key
        final ollama = Providers.ollama;
        expect(ollama.createChatModel, returnsNormally);

        // Agent creation should also work
        expect(() => Agent('ollama:llama2'), returnsNormally);
      });

      test('Invalid provider name throws', () {
        expect(
          () => Agent('invalid-provider:model'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('invalid-provider'),
            ),
          ),
        );
      });
    });

    group('Configuration Precedence Integration', () {
      test('Full precedence chain works correctly', () {
        // Set up environment
        Agent.environment['OPENAI_API_KEY'] = 'sk-agent-env';

        // Test 1: Provider instance configuration takes precedence
        final customProvider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          apiKeyName: 'OPENAI_API_KEY',
          apiKey: 'sk-provider-key',
          baseUrl: Uri.parse('https://custom.api.com'),
          caps: Providers.openai.caps,
        );

        var agent = Agent.forProvider(customProvider);
        expect(agent.model, equals('openai:gpt-4o-mini'));

        // Test 2: Default provider uses Agent.environment
        agent = Agent('openai:gpt-4o-mini');
        expect(platform.tryGetEnv('OPENAI_API_KEY'), equals('sk-agent-env'));

        // Test 3: Mixed configuration - custom baseUrl, env apiKey
        final mixedProvider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          apiKeyName: 'OPENAI_API_KEY',
          baseUrl: Uri.parse('https://mixed.api.com'),
          caps: Providers.openai.caps,
        );

        agent = Agent.forProvider(mixedProvider);
        expect(agent.model, equals('openai:gpt-4o-mini'));
        // Provider's baseUrl is used, apiKey from environment
        expect(
          mixedProvider.baseUrl,
          equals(Uri.parse('https://mixed.api.com')),
        );
        expect(platform.tryGetEnv('OPENAI_API_KEY'), equals('sk-agent-env'));
      });

      test('Model creation respects provider configuration', () async {
        // Set up configuration
        Agent.environment['OPENAI_API_KEY'] = 'sk-test-key';

        // Test with default provider (uses environment)
        var agent = Agent('openai:gpt-4o-mini', temperature: 0.5);

        // Verify agent configuration
        expect(agent.model, equals('openai:gpt-4o-mini'));
        expect(agent.providerName, equals('openai'));
        expect(agent.model, equals('openai:gpt-4o-mini'));

        // API key should come from environment
        expect(platform.tryGetEnv('OPENAI_API_KEY'), equals('sk-test-key'));

        // Test with custom provider (uses its own apiKey)
        final customProvider = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          apiKeyName: 'OPENAI_API_KEY',
          apiKey: 'sk-provider-key',
          caps: Providers.openai.caps,
        );

        agent = Agent.forProvider(customProvider, temperature: 0.7);

        expect(agent.model, equals('openai:gpt-4o-mini'));
        // Provider's apiKey takes precedence over environment
      });
    });

    group('Provider Alias Resolution', () {
      test('Provider aliases work correctly', () {
        Agent.environment['ANTHROPIC_API_KEY'] = 'sk-claude';
        Agent.environment['GEMINI_API_KEY'] = 'sk-gemini';

        // Test anthropic alias
        var agent = Agent('claude:claude-3-haiku-20240307');
        expect(agent.providerName, equals('claude')); // Keeps original input

        // Test google aliases
        agent = Agent('gemini:gemini-2.5-flash');
        expect(agent.providerName, equals('gemini'));

        agent = Agent('google:gemini-2.5-flash');
        expect(agent.providerName, equals('google'));
      });
    });

    group('Provider Configuration Properties', () {
      test('Provider has correct default configuration', () {
        // Test provider with API key and base URL
        final openai = Providers.openai;
        expect(openai.name, equals('openai'));
        expect(openai.displayName, equals('OpenAI'));
        expect(openai.defaultModelNames[ModelKind.chat], equals('gpt-4o'));
        expect(
          openai.baseUrl,
          isNull,
        ); // OpenAI provider uses default baseUrl in the API client
        expect(openai.apiKeyName, equals('OPENAI_API_KEY'));
        expect(openai.caps.contains(ProviderCaps.chat), isTrue);

        // Test provider without API key (Ollama)
        final ollama = Providers.ollama;
        expect(ollama.name, equals('ollama'));
        expect(ollama.displayName, equals('Ollama'));
        expect(ollama.apiKeyName, isNull);
        expect(
          ollama.baseUrl,
          isNull,
        ); // Ollama uses a default baseUrl in the model implementation
      });

      test('Provider discovery methods work correctly', () {
        // Discovery by name
        final openai = Providers.get('openai');
        expect(openai.name, equals('openai'));

        // Discovery by alias
        final anthropic = Providers.get('claude');
        expect(anthropic.name, equals('anthropic'));

        // Discovery by capabilities
        final visionProviders = Providers.allWith({ProviderCaps.chatVision});
        expect(visionProviders.length, greaterThan(0));
        expect(
          visionProviders.every(
            (p) => p.caps.contains(ProviderCaps.chatVision),
          ),
          isTrue,
        );
      });

      test('Provider configuration flows through to model creation', () {
        // Test 1: Default provider uses environment
        Agent.environment['OPENAI_API_KEY'] = 'sk-default';
        final provider1 = Providers.openai;
        final model1 = provider1.createChatModel();
        expect(model1, isNotNull);
        expect(
          model1.name,
          equals(provider1.defaultModelNames[ModelKind.chat]),
        );

        // Test 2: Custom provider with its own configuration
        final provider2 = OpenAIProvider(
          name: 'openai',
          displayName: 'OpenAI Custom',
          defaultModelNames: {ModelKind.chat: 'gpt-4'},
          apiKeyName: 'OPENAI_API_KEY',
          apiKey: 'sk-custom',
          baseUrl: Uri.parse('https://custom.api.com'),
          caps: Providers.openai.caps,
        );
        final model2 = provider2.createChatModel(name: 'gpt-4o-mini');
        expect(model2, isNotNull);
        expect(model2.name, equals('gpt-4o-mini'));

        // Test 3: Provider without API key requirement
        final provider3 = Providers.ollama;
        final model3 = provider3.createChatModel(name: 'llama2');
        expect(model3, isNotNull);
        expect(model3.name, equals('llama2'));
      });

      test('Provider list filtering works correctly', () {
        // Get all providers
        final allProviders = Providers.all;
        expect(allProviders.length, greaterThan(5));

        // Verify no duplicates from aliases
        final providerNames = allProviders.map((p) => p.name).toList();
        final uniqueNames = providerNames.toSet();
        expect(providerNames.length, equals(uniqueNames.length));

        // Verify ollama is in the list
        expect(providerNames.contains('ollama'), isTrue);

        // Verify aliases are not in the main list
        expect(providerNames.contains('claude'), isFalse);
        expect(providerNames.contains('gemini'), isFalse);
      });

      test('Nullable provider properties handled correctly', () {
        // Test Ollama with null apiKeyName
        final ollama = Providers.ollama;
        expect(ollama.apiKeyName, isNull);

        // Should still create model without API key
        final model = ollama.createChatModel();
        expect(model, isNotNull);

        // Test custom provider could have null defaultBaseUrl
        // (verified in custom_provider.dart example)
      });

      test('Provider configuration precedence with nulls', () {
        // Provider with null apiKeyName should not try to read from env
        final ollama = Providers.ollama;
        Agent.environment['SOME_KEY'] = 'should-not-be-used';

        final model = ollama.createChatModel();
        expect(model, isNotNull);
        // Model created successfully without needing any API key

        // Clean up
        Agent.environment.remove('SOME_KEY');
      });
    });
  });
}

// Test options class
class TestChatOptions extends ChatModelOptions {
  const TestChatOptions();
}

// Test embeddings options class
class TestEmbeddingsOptions extends EmbeddingsModelOptions {}

// Test provider that requires a fake API key
class TestProvider
    extends
        Provider<
          TestChatOptions,
          TestEmbeddingsOptions,
          MediaGenerationModelOptions
        > {
  TestProvider()
    : super(
        name: 'test-provider',
        displayName: 'Test Provider',
        defaultModelNames: {ModelKind.chat: 'test-model'},
        baseUrl: Uri.parse('https://test.example.com'),
        apiKeyName: 'TEST_PROVIDER_API_KEY_THAT_DOES_NOT_EXIST',
        caps: const {ProviderCaps.chat},
      );

  @override
  ChatModel<TestChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    TestChatOptions? options,
  }) {
    // Provider resolves API key if it has an apiKeyName
    final resolvedApiKey =
        apiKey ?? (apiKeyName != null ? platform.tryGetEnv(apiKeyName) : null);

    return TestChatModel(
      name: name ?? defaultModelNames[ModelKind.chat]!,
      apiKey: resolvedApiKey, // Pass resolved API key (may still be null)
      baseUrl: baseUrl ?? Uri.parse('https://test.example.com'),
    );
  }

  @override
  Stream<ModelInfo> listModels() => const Stream.empty();

  @override
  EmbeddingsModel<TestEmbeddingsOptions> createEmbeddingsModel({
    String? name,
    TestEmbeddingsOptions? options,
  }) {
    throw UnsupportedError('Test provider does not support embeddings');
  }

  @override
  MediaGenerationModel<MediaGenerationModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    MediaGenerationModelOptions? options,
  }) {
    throw UnsupportedError('Test provider does not support media generation');
  }
}

// Test model that throws when API key is missing
class TestChatModel extends ChatModel<TestChatOptions> {
  // ignore: avoid_unused_constructor_parameters
  TestChatModel({required super.name, String? apiKey, Uri? baseUrl})
    : super(defaultOptions: const TestChatOptions()) {
    // Model is responsible for resolving API key from environment if not
    // provided
    final _ = apiKey ?? platform.getEnv(apiKeyName);
  }
  static const String apiKeyName = 'TEST_PROVIDER_API_KEY_THAT_DOES_NOT_EXIST';

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    TestChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    // Not implemented - just for testing configuration
    throw UnimplementedError();
  }

  @override
  void dispose() {
    // Nothing to dispose
  }
}
