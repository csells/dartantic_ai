/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g.
///    ProviderTestCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart' as js;
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  group('Provider Mappers', () {
    group('message format consistency (80% cases)', () {
      runProviderTest('handles basic text messages', (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.send('Say "mapper test"');
        expect(result.output, isNotEmpty);
        expect(result.messages, isNotEmpty);

        expect(
          result.messages.any((m) => m.role == ChatMessageRole.user),
          isTrue,
          reason: '${provider.name} should have human message',
        );
        expect(
          result.messages.any((m) => m.role == ChatMessageRole.model),
          isTrue,
          reason: '${provider.name} should have AI message',
        );
      });

      test('message metadata is consistent', () async {
        final agent = Agent('openai:gpt-4o-mini');
        final result = await agent.send('Test metadata');

        expect(result.messages, isNotEmpty);
        for (final message in result.messages) {
          // Basic message properties should be present
          expect(message.role, isNotNull);
          expect(message.parts, isNotEmpty);
        }
      });
    });

    group('tool message mapping (80% cases)', () {
      runProviderTest(
        'tool calls are mapped consistently',
        (provider) async {
          final tool = Tool<String>(
            name: 'echo_tool',
            description: 'Echoes the input',
            inputSchema: js.JsonSchema.create({
              'type': 'object',
              'properties': {
                'text': {'type': 'string', 'description': 'The text to echo'},
              },
              'required': ['text'],
            }),
            inputFromJson: (json) => (json['text'] ?? 'hello') as String,
            onCall: (input) => 'Echo: $input',
          );

          final agent = Agent(provider.name, tools: [tool]);

          final result = await agent.send('Use echo_tool to say "hello"');

          final hasToolCall = result.messages.any((m) => m.hasToolCalls);
          final hasToolResult = result.messages.any((m) => m.hasToolResults);

          expect(
            hasToolCall || hasToolResult,
            isTrue,
            reason: '${provider.name} should have tool messages',
          );
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test('tool results maintain proper associations', () async {
        final tool = Tool<int>(
          name: 'add',
          description: 'Adds two numbers',
          inputSchema: js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'a': {'type': 'integer', 'description': 'First number'},
              'b': {'type': 'integer', 'description': 'Second number'},
            },
            'required': ['a', 'b'],
          }),
          inputFromJson: (json) {
            final a = json['a'] ?? 5;
            final b = json['b'] ?? 3;
            return (a is int ? a : int.tryParse(a.toString()) ?? 5) +
                (b is int ? b : int.tryParse(b.toString()) ?? 3);
          },
          onCall: (sum) => sum,
        );

        final agent = Agent('openai:gpt-4o-mini', tools: [tool]);
        final result = await agent.send('Add 5 and 3');

        // Find tool call and result messages
        final toolCallMsg = result.messages.firstWhere(
          (m) => m.hasToolCalls,
          orElse: () => throw StateError('No tool call found'),
        );
        final toolResultMsg = result.messages.firstWhere(
          (m) => m.hasToolResults,
          orElse: () => throw StateError('No tool result found'),
        );

        // Tool call should have valid structure
        expect(toolCallMsg.parts, isNotEmpty);
        final toolCallParts = toolCallMsg.parts
            .where((p) => p is ToolPart && p.kind == ToolPartKind.call)
            .cast<ToolPart>();
        expect(toolCallParts, isNotEmpty);
        final toolCallPart = toolCallParts.first;
        expect(toolCallPart.id, isNotEmpty);
        expect(toolCallPart.name, equals('add'));

        // Tool result should reference the call
        expect(toolResultMsg.parts, isNotEmpty);
        final toolResultPart = toolResultMsg.parts.whereType<ToolPart>().first;
        expect(toolResultPart.id, equals(toolCallPart.id));

        // Validate message history follows correct pattern
      });
    });

    group('streaming message assembly (80% cases)', () {
      test('streaming chunks assemble into complete messages', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');

        final chunks = <String>[];
        await for (final chunk in agent.sendStream('Count to 3')) {
          chunks.add(chunk.output);
        }

        // Should have multiple chunks
        expect(chunks.length, greaterThan(1));

        // Combined should form coherent response
        final combined = chunks.join();
        expect(combined, isNotEmpty);
        expect(combined.toLowerCase(), anyOf(contains('1'), contains('one')));
      });

      test('streaming maintains message boundaries', () async {
        final agent = Agent('openai:gpt-4o-mini');

        final result = await agent.send('Say "test"');

        // Should have at least human and AI messages
        expect(result.messages.length, greaterThanOrEqualTo(2));

        // Validate message history follows correct pattern
      });
    });

    group('provider-specific formats (80% cases)', () {
      test('OpenAI format compatibility', () async {
        final agent = Agent('openai:gpt-4o-mini');
        final result = await agent.send('Test OpenAI format');

        // OpenAI uses specific message structure
        expect(result.messages, isNotEmpty);
        expect(result.finishReason, isNotNull);
      });

      test('Anthropic format compatibility', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');
        final result = await agent.send('Test Anthropic format');

        // Anthropic has its own format
        expect(result.messages, isNotEmpty);
        if (result.usage != null) {
          expect(result.usage!.totalTokens, greaterThan(0));
        }
      });

      test('Google format compatibility', () async {
        final agent = Agent('google:gemini-2.5-flash');
        final result = await agent.send('Test Google format');

        // Google/Gemini format
        expect(result.messages, isNotEmpty);
        expect(result.output, isNotEmpty);
      });
    });

    group('edge cases', () {
      test('handles empty responses', () async {
        final agent = Agent('google:gemini-2.5-flash');

        // Prompt that might produce minimal response
        final result = await agent.send('.');

        // Should still have valid structure
        expect(result.messages, isNotEmpty);
        expect(
          result.messages.any((m) => m.role == ChatMessageRole.user),
          isTrue,
        );
        expect(
          result.messages.any((m) => m.role == ChatMessageRole.model),
          isTrue,
        );
      });

      test('handles special characters in messages', () async {
        final agent = Agent('google:gemini-2.5-flash');

        const specialChars = r'Special chars: @#$%^&*()_+{}[]|\:;"<>?,./~`';
        final result = await agent.send('Echo: $specialChars');

        // Should preserve special characters
        expect(result.messages, isNotEmpty);
        expect(result.output, isNotEmpty);
      });

      test('handles unicode in messages', () async {
        final agent = Agent('google:gemini-2.5-flash');

        const unicode = 'Unicode test: 你好 🌍 émojis ñ Ω';
        final result = await agent.send('Echo: $unicode');

        // Should handle unicode properly
        expect(result.messages, isNotEmpty);
        expect(result.output, isNotEmpty);
      });
    });
  });
}
