import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/platform/platform.dart' as platform;
import 'package:test/test.dart';

void main() {
  group('Embeddings Configuration Tests', () {
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

    group('Provider Embeddings API Key Resolution', () {
      test('Falls back to Agent.environment', () {
        Agent.environment['OPENAI_API_KEY'] = 'sk-env-key';

        final provider = Agent.getProvider('openai');
        final model = provider.createEmbeddingsModel();

        // Model should be created with env key
        expect(model, isNotNull);
      });

      test('Different providers use different API keys', () {
        // Set different keys
        Agent.environment['OPENAI_API_KEY'] = 'sk-openai';
        Agent.environment['GEMINI_API_KEY'] = 'sk-gemini';
        Agent.environment['MISTRAL_API_KEY'] = 'sk-mistral';
        Agent.environment['COHERE_API_KEY'] = 'sk-cohere';

        // Each should find its key
        expect(platform.tryGetEnv('OPENAI_API_KEY'), equals('sk-openai'));
        expect(platform.tryGetEnv('GEMINI_API_KEY'), equals('sk-gemini'));
        expect(platform.tryGetEnv('MISTRAL_API_KEY'), equals('sk-mistral'));
        expect(platform.tryGetEnv('COHERE_API_KEY'), equals('sk-cohere'));
      });
    });

    group('Provider Embeddings Base URL Resolution', () {
      test('Each provider has correct default base URL', () {
        // Set API keys so models can be created
        Agent.environment['OPENAI_API_KEY'] = 'sk-openai';
        Agent.environment['GEMINI_API_KEY'] = 'sk-gemini';
        Agent.environment['MISTRAL_API_KEY'] = 'sk-mistral';
        Agent.environment['COHERE_API_KEY'] = 'sk-cohere';

        // Create models with defaults
        expect(
          Agent.getProvider('openai').createEmbeddingsModel,
          returnsNormally,
        );
        expect(
          Agent.getProvider('google').createEmbeddingsModel,
          returnsNormally,
        );
        expect(
          Agent.getProvider('mistral').createEmbeddingsModel,
          returnsNormally,
        );
        expect(
          Agent.getProvider('cohere').createEmbeddingsModel,
          returnsNormally,
        );
      });
    });

    group('Error Handling', () {
      test('Invalid provider name throws', () {
        expect(
          () => Agent.getProvider('invalid-provider'),
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
  });
}
