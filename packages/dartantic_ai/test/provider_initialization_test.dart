import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

void main() {
  group('Provider Initialization', () {
    setUp(() {
      // Use only Agent.environment for testing
      Agent.useAgentEnvironmentOnly = true;
      // Clear any existing environment variables
      Agent.environment.clear();
    });

    tearDown(() {
      // Restore default behavior
      Agent.useAgentEnvironmentOnly = false;
      Agent.environment.clear();
    });

    test('Can access provider metadata without API keys', () {
      // This should NOT throw even if API keys are not set
      expect(() => Providers.get('google'), returnsNormally);
      expect(() => Providers.get('mistral'), returnsNormally);
      expect(() => Providers.get('anthropic'), returnsNormally);
      expect(() => Providers.get('cohere'), returnsNormally);

      // Should be able to access provider properties
      final googleProvider = Providers.get('google');
      expect(googleProvider.name, equals('google'));
      expect(googleProvider.displayName, equals('Google'));
      expect(googleProvider.apiKeyName, equals('GEMINI_API_KEY'));
    });

    test('Can list all providers without API keys', () {
      // This should NOT throw even if API keys are not set
      expect(() => Providers.all, returnsNormally);
      expect(Providers.all.length, greaterThan(0));
    });

    test('Throws when creating model without required API key', () {
      final provider = Providers.get('google') as GoogleProvider;

      // Assume GEMINI_API_KEY is not set in test environment
      expect(
        provider.createChatModel,
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('GEMINI_API_KEY is required'),
          ),
        ),
      );
    });

    test('Ollama provider works without API key', () {
      final provider = Providers.get('ollama');

      // Should not throw since Ollama doesn't require API key
      expect(provider.createChatModel, returnsNormally);
    });

    test('Can use Agent with specific provider without others failing', () {
      // This was the original issue - trying to use google provider
      // but getting error about MISTRAL_API_KEY

      // This should work even if MISTRAL_API_KEY is not set
      expect(() => Agent('google:gemini-2.5-flash'), returnsNormally);

      // But trying to actually send a message should fail with proper error
      final agent = Agent('google:gemini-2.5-flash');
      expect(
        () => agent.send('Hello'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('GEMINI_API_KEY is required'),
          ),
        ),
      );
    });

    test('Providers are lazily initialized', () {
      // Access only the google provider
      final googleProvider = Providers.get('google');
      expect(googleProvider.displayName, equals('Google'));

      // Verify we can create an agent without triggering other provider
      // initialization
      expect(() => Agent('google:gemini-2.5-flash'), returnsNormally);

      // Now access all providers - this triggers initialization of all
      final allProviders = Providers.all;
      expect(allProviders.length, equals(11));

      // Verify we can still use a specific provider
      expect(() => Agent('anthropic:claude-3-5-sonnet'), returnsNormally);
    });
  });
}
