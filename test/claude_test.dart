// ignore_for_file: avoid_print

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('Claude/Anthropic Integration Tests', () {
    group('Basic Claude Integration', () {
      test('Hello World Example', () async {
        final agent = Agent(
          'claude',
          systemPrompt: 'Be concise, reply with one sentence.',
        );

        final output = StringBuffer();
        var messages = <Message>[];
        await for (final chunk in agent.runStreamWithRetries(
          'Where does "hello world" come from?',
        )) {
          output.write(chunk.output);
          messages = chunk.messages;
        }
        final resultOutput = output.toString();
        print('Claude resultOutput: $resultOutput');
        print('Claude messages: $messages');
        expect(resultOutput, isNotEmpty);
        expect(RegExp(r'\.').allMatches(resultOutput).length, equals(1));
      });

      test('Claude with JSON Schema Output', () async {
        final outputSchema = <String, dynamic>{
          'type': 'object',
          'properties': {
            'town': {'type': 'string'},
            'country': {'type': 'string'},
          },
          'required': ['town', 'country'],
          'additionalProperties': false,
        };

        // Claude doesn't support structured output, so this should throw
        // an error
        expect(
          () => Agent('claude', outputSchema: outputSchema.toSchema()),
          throwsA(isA<AssertionError>()),
        );
        print('Claude correctly rejects JSON Schema output (not supported)');
      });

      test('Claude with Typed Object Output', () async {
        final tncSchema = <String, dynamic>{
          'type': 'object',
          'properties': {
            'town': {'type': 'string'},
            'country': {'type': 'string'},
          },
          'required': ['town', 'country'],
          'additionalProperties': false,
        };

        // Claude doesn't support structured output, so this should throw
        // an error
        expect(
          () => Agent(
            'claude',
            outputSchema: tncSchema.toSchema(),
            outputFromJson:
                (json) => {
                  'town': json['town'] as String,
                  'country': json['country'] as String,
                },
          ),
          throwsA(isA<AssertionError>()),
        );
        print('Claude correctly rejects typed object output (not supported)');
      });

      test('Claude Tool Usage Example', () async {
        final agent = Agent(
          'claude',
          systemPrompt:
              'Be sure to include the name of the location in your response. '
              'Show the time as local time. '
              'Do not ask any follow up questions.',
          tools: [
            Tool(
              name: 'time',
              description: 'Get the current time in a given time zone',
              inputSchema:
                  {
                    'type': 'object',
                    'properties': {
                      'timeZoneName': {
                        'type': 'string',
                        'description':
                            'The name of the time zone (e.g. "America/New_York")',
                      },
                    },
                    'required': ['timeZoneName'],
                  }.toSchema(),
              onCall:
                  (input) async => {'time': DateTime.now().toIso8601String()},
            ),
            Tool(
              name: 'temp',
              description: 'Get the current temperature in a given location',
              inputSchema:
                  {
                    'type': 'object',
                    'properties': {
                      'location': {
                        'type': 'string',
                        'description': 'The location to get temperature for',
                      },
                    },
                    'required': ['location'],
                  }.toSchema(),
              onCall: (input) async => {'temperature': 72}, // Mock temperature
            ),
          ],
        );

        final output = StringBuffer();
        await for (final chunk in agent.runStreamWithRetries(
          'What is the time and temperature in New York City?',
        )) {
          output.write(chunk.output);
        }
        final resultOutput = output.toString();
        print('Claude tool usage output: $resultOutput');
        expect(resultOutput, isNotEmpty);
        expect(resultOutput, contains('New York'));
      });

      test('Claude with specific model', () async {
        final agent = Agent(
          'anthropic:claude-3-5-sonnet-20241022',
          systemPrompt: 'Be concise, reply with one sentence.',
        );

        final output = StringBuffer();
        var messages = <Message>[];
        await for (final chunk in agent.runStreamWithRetries(
          'The windy city in the US of A.',
        )) {
          output.write(chunk.output);
          messages = chunk.messages;
        }
        final resultOutput = output.toString();
        print('Claude specific model output: $resultOutput');
        expect(resultOutput, isNotEmpty);
        expect(resultOutput, contains('Chicago'));
        expect(messages, isNotEmpty);
      });

      test('Claude provider aliases work', () async {
        // Test 'claude' alias
        final claudeAgent = Agent('claude', systemPrompt: 'Be concise.');
        final claudeResult = await claudeAgent.runWithRetries('Hello');
        expect(claudeResult.output, isNotEmpty);
        print('Claude alias result: ${claudeResult.output}');

        // Test 'claude-ai' alias
        final claudeAiAgent = Agent('claude-ai', systemPrompt: 'Be concise.');
        final claudeAiResult = await claudeAiAgent.runWithRetries('Hello');
        expect(claudeAiResult.output, isNotEmpty);
        print('Claude-ai alias result: ${claudeAiResult.output}');

        // Test 'anthropic' provider name
        final anthropicAgent = Agent('anthropic', systemPrompt: 'Be concise.');
        final anthropicResult = await anthropicAgent.runWithRetries('Hello');
        expect(anthropicResult.output, isNotEmpty);
        print('Anthropic provider result: ${anthropicResult.output}');
      });
    });

    group('Claude Provider Capabilities', () {
      test('Claude provider should support expected capabilities', () {
        final provider = Agent.providerFor('anthropic');
        final agent = Agent.provider(provider);

        // Claude should support most capabilities except embeddings
        expect(agent.caps, contains(ProviderCaps.textGeneration));
        expect(agent.caps, isNot(contains(ProviderCaps.embeddings)));
        expect(agent.caps, contains(ProviderCaps.chat));
        expect(agent.caps, contains(ProviderCaps.fileUploads));
        expect(agent.caps, contains(ProviderCaps.tools));

        // Check embedding support specifically
        final supportsEmbeddings = agent.caps.contains(ProviderCaps.embeddings);
        expect(supportsEmbeddings, isFalse);

        print('Claude capabilities: ${agent.caps}');
      });

      test('Claude embedding operations should fail gracefully', () async {
        final agent = Agent('claude');

        // Check capabilities first
        final supportsEmbeddings = agent.caps.contains(ProviderCaps.embeddings);
        expect(
          supportsEmbeddings,
          isFalse,
          reason: 'Claude should not support embeddings',
        );

        // Should throw a descriptive error when attempting embeddings
        expect(
          () async =>
              agent.createEmbedding('Test text', type: EmbeddingType.document),
          throwsA(isA<UnsupportedError>()),
        );

        print('Claude correctly fails embedding operations');
      });

      test('Claude provider listModels returns known models', () async {
        final provider = Agent.providerFor('claude') as AnthropicProvider;
        final models = await provider.listModels();

        expect(models, isNotEmpty);
        expect(models.length, greaterThan(5));

        // Check for some known Claude models
        final modelNames = models.map((m) => m.name).toList();
        expect(modelNames, contains('claude-3-5-sonnet-20241022'));
        expect(modelNames, contains('claude-3-haiku-20240307'));
        expect(modelNames, contains('claude-3-opus-20240229'));

        print('Claude models: ${modelNames.join(', ')}');
      });
    });
  });
}
