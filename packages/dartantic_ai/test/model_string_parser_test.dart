import 'package:dartantic_ai/src/agent/model_string_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ModelStringParser - Happy Paths', () {
    test('providerName', () {
      final parser = ModelStringParser.parse('providerName');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
    });

    test('providerName:chatModelName', () {
      final parser = ModelStringParser.parse('providerName:chatModelName');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chatModelName');
      expect(parser.embeddingsModelName, null);
    });

    test('providerName/chatModelName', () {
      final parser = ModelStringParser.parse('providerName/chatModelName');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chatModelName');
      expect(parser.embeddingsModelName, null);
    });

    test('providerName?chat=chatModelName', () {
      final parser = ModelStringParser.parse('providerName?chat=chatModelName');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chatModelName');
      expect(parser.embeddingsModelName, null);
    });

    test('providerName?embeddings=embeddingsModelName', () {
      final parser = ModelStringParser.parse(
        'providerName?embeddings=embeddingsModelName',
      );
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, 'embeddingsModelName');
    });

    test('providerName?chat=chatModelName&embeddings=embeddingsModelName', () {
      final parser = ModelStringParser.parse(
        'providerName?chat=chatModelName&embeddings=embeddingsModelName',
      );
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chatModelName');
      expect(parser.embeddingsModelName, 'embeddingsModelName');
      expect(parser.mediaModelName, null);
    });

    test('providerName?media=mediaModelName', () {
      final parser = ModelStringParser.parse(
        'providerName?media=mediaModelName',
      );
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
      expect(parser.mediaModelName, 'mediaModelName');
      expect(
        ModelStringParser(
          'providername',
          mediaModelName: 'mediaModelName',
        ).toString(),
        'providername?media=mediaModelName',
      );
    });
  });

  group('ModelStringParser - Edge Cases', () {
    test('empty string throws', () {
      expect(() => ModelStringParser.parse(''), throwsA(isA<Exception>()));
    });

    test('whitespace string', () {
      final parser = ModelStringParser.parse('   ');
      expect(parser.providerName, '   ');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
    });

    test('providerName: (empty chat model)', () {
      final parser = ModelStringParser.parse('providerName:');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
    });

    test('providerName:chat1/chat2', () {
      final parser = ModelStringParser.parse('providerName:chat1/chat2');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chat1/chat2');
      expect(parser.embeddingsModelName, null);
    });

    test('providerName//segment throws (empty segment)', () {
      expect(
        () => ModelStringParser.parse('providerName//segment'),
        throwsA(isA<Exception>()),
      );
    });

    test('providerName:chat1/chat2', () {
      final parser = ModelStringParser.parse('providerName:chat1/chat2');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chat1/chat2');
      expect(parser.embeddingsModelName, null);
    });

    test('providerName?chat=chatModel&embeddings= (empty embeddings)', () {
      final parser = ModelStringParser.parse(
        'providerName?chat=chatModel&embeddings=',
      );
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chatModel');
      expect(parser.embeddingsModelName, null);
    });

    test('providerName:chat:extra (multiple colons)', () {
      final parser = ModelStringParser.parse('providerName:chat:extra');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'chat:extra');
      expect(parser.embeddingsModelName, null);
    });

    test('providerName with slash in name', () {
      final parser = ModelStringParser.parse('pro/vider:gpt-3.5');
      expect(parser.providerName, 'pro');
      expect(parser.chatModelName, 'vider:gpt-3.5');
      expect(parser.embeddingsModelName, null);
    });
  });
  group('ModelStringParser - OpenAI Models', () {
    test('OpenAI chat model with query parameter', () {
      final parser = ModelStringParser.parse('openai?chat=gpt-4o');
      expect(parser.providerName, 'openai');
      expect(parser.chatModelName, 'gpt-4o');
      expect(parser.embeddingsModelName, null);
    });

    test('OpenAI embeddings model', () {
      final parser = ModelStringParser.parse(
        'openai?embeddings=text-embedding-3-small',
      );
      expect(parser.providerName, 'openai');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, 'text-embedding-3-small');
    });

    test('OpenAI chat model with plain slash', () {
      final parser = ModelStringParser.parse('openai/gpt-3.5-turbo');
      expect(parser.providerName, 'openai');
      expect(parser.chatModelName, 'gpt-3.5-turbo');
      expect(parser.embeddingsModelName, null);
    });

    test('OpenAI chat model with colon', () {
      final parser = ModelStringParser.parse('openai:gpt-4');
      expect(parser.providerName, 'openai');
      expect(parser.chatModelName, 'gpt-4');
      expect(parser.embeddingsModelName, null);
    });

    test('OpenAI media model with query parameter', () {
      final parser = ModelStringParser.parse('openai?media=unknown');
      expect(parser.providerName, 'openai');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
      expect(parser.mediaModelName, 'unknown');
    });

    test('OpenAI legacy other parameter maps to media', () {
      final parser = ModelStringParser.parse('openai?other=legacy');
      expect(parser.providerName, 'openai');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
      expect(parser.mediaModelName, 'legacy');
    });

    test('OpenAI chat model with multiple query parameters', () {
      final parser = ModelStringParser.parse('openai?chat=gpt-4o&media=custom');
      expect(parser.providerName, 'openai');
      expect(parser.chatModelName, 'gpt-4o');
      expect(parser.embeddingsModelName, null);
      expect(parser.mediaModelName, 'custom');
    });
  });

  group('ModelStringParser - OpenRouter Models', () {
    test('OpenRouter chat model with query parameter', () {
      final parser = ModelStringParser.parse(
        'openrouter?chat=anthropic/claude-opus-4',
      );
      expect(parser.providerName, 'openrouter');
      expect(parser.chatModelName, 'anthropic/claude-opus-4');
      expect(parser.embeddingsModelName, null);
    });

    test('OpenRouter chat model without prefix', () {
      final parser = ModelStringParser.parse(
        'openrouter:qwen/qwen3-235b-a22b-thinking-2507',
      );
      expect(parser.providerName, 'openrouter');
      expect(parser.chatModelName, 'qwen/qwen3-235b-a22b-thinking-2507');
      expect(parser.embeddingsModelName, null);
    });

    test('OpenRouter embeddings model', () {
      final parser = ModelStringParser.parse(
        'openrouter?embeddings=mistral-embed',
      );
      expect(parser.providerName, 'openrouter');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, 'mistral-embed');
    });

    test('OpenRouter unrecognized format', () {
      final parser = ModelStringParser.parse('openrouter:unrecognized/segment');
      expect(parser.providerName, 'openrouter');
      expect(parser.chatModelName, 'unrecognized/segment');
      expect(parser.embeddingsModelName, null);
    });
  });

  group('ModelStringParser - Mistral Models', () {
    test('Mistral chat model with query parameter', () {
      final parser = ModelStringParser.parse(
        'mistral?chat=mistral-medium-2505',
      );
      expect(parser.providerName, 'mistral');
      expect(parser.chatModelName, 'mistral-medium-2505');
      expect(parser.embeddingsModelName, null);
    });

    test('Mistral embeddings model', () {
      final parser = ModelStringParser.parse(
        'mistral?embeddings=mistral-embed',
      );
      expect(parser.providerName, 'mistral');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, 'mistral-embed');
    });

    test('Mistral other model (plain segment)', () {
      final parser = ModelStringParser.parse('mistral:pixtral-large-2411');
      expect(parser.providerName, 'mistral');
      expect(parser.chatModelName, 'pixtral-large-2411');
      expect(parser.embeddingsModelName, null);
    });
  });

  group('ModelStringParser - Google Models', () {
    test('Google chat model with query parameter', () {
      final parser = ModelStringParser.parse(
        'google?chat=models/gemini-1.5-pro-latest',
      );
      expect(parser.providerName, 'google');
      expect(parser.chatModelName, 'models/gemini-1.5-pro-latest');
      expect(parser.embeddingsModelName, null);
    });

    test('Google embeddings model', () {
      final parser = ModelStringParser.parse(
        'google?embeddings=models/text-embedding-004',
      );
      expect(parser.providerName, 'google');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, 'models/text-embedding-004');
    });

    test('Google chat model with slash throws (multiple segments)', () {
      expect(
        () => ModelStringParser.parse('google/models/gemini-1.5-pro'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ModelStringParser - More Edge Cases', () {
    test('Empty string throws', () {
      expect(() => ModelStringParser.parse(''), throwsA(isA<Exception>()));
    });

    test('Whitespace string', () {
      final parser = ModelStringParser.parse('   ');
      expect(parser.providerName, '   ');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
    });

    test('Provider with empty chat model', () {
      final parser = ModelStringParser.parse('providerName:');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
    });

    test('Provider with empty embeddings model', () {
      final parser = ModelStringParser.parse('providerName?embeddings=');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, null);
    });

    test('Multiple colons in chat model', () {
      final parser = ModelStringParser.parse('providerName:model:extra');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'model:extra');
      expect(parser.embeddingsModelName, null);
    });

    test('Slash in provider name throws', () {
      expect(
        () => ModelStringParser.parse('pro/vider/model'),
        throwsA(isA<Exception>()),
      );
    });

    test('Unrecognized prefix sets chat if null', () {
      final parser = ModelStringParser.parse('providerName/other:model');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'other:model');
      expect(parser.embeddingsModelName, null);
    });

    test('Multiple query parameters', () {
      final parser = ModelStringParser.parse('providerName?chat=one&media=two');
      expect(parser.providerName, 'providername');
      expect(parser.chatModelName, 'one');
      expect(parser.mediaModelName, 'two');
      expect(parser.embeddingsModelName, null);
    });
  });

  group('ModelStringParser - Other Providers', () {
    test('Anthropic chat model', () {
      final parser = ModelStringParser.parse(
        'anthropic?chat=claude-3.5-sonnet',
      );
      expect(parser.providerName, 'anthropic');
      expect(parser.chatModelName, 'claude-3.5-sonnet');
      expect(parser.embeddingsModelName, null);
    });

    test('Cohere embeddings model', () {
      final parser = ModelStringParser.parse('cohere?embeddings=embed-v4.0');
      expect(parser.providerName, 'cohere');
      expect(parser.chatModelName, null);
      expect(parser.embeddingsModelName, 'embed-v4.0');
    });

    test('Ollama chat model with colon in model name', () {
      final parser = ModelStringParser.parse('ollama:llama3.2:latest');
      expect(parser.providerName, 'ollama');
      expect(parser.chatModelName, 'llama3.2:latest');
      expect(parser.embeddingsModelName, null);
    });

    test('Together AI chat model with slash', () {
      final parser = ModelStringParser.parse(
        'together:meta-llama/Llama-3.3-70B-Instruct-Turbo-Free',
      );
      expect(parser.providerName, 'together');
      expect(
        parser.chatModelName,
        'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free',
      );
      expect(parser.embeddingsModelName, null);
    });
  });
}
