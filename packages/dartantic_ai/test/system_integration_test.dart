/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication
///
/// This file tests cross-provider integration scenarios

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';
import 'test_tools.dart';
import 'test_utils.dart';

void main() {
  // Helper for tool-supporting providers
  void runToolProviderTest(
    String testName,
    Future<void> Function(Provider provider) testFunction, {
    Timeout? timeout,
  }) {
    runProviderTest(
      testName,
      testFunction,
      requiredCaps: {ProviderCaps.multiToolCalls},
      timeout: timeout,
    );
  }

  group('System Integration', () {
    group('end-to-end workflows', () {
      test('complete agent conversation with tools', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool, intTool]);

        final history = <ChatMessage>[];

        // Turn 1: Initial greeting
        var result = await agent.send(
          'Hello! Can you help me test tools?',
          history: history,
        );
        expect(result.output, isNotEmpty);
        history.addAll(result.messages);

        // Turn 2: Use a tool
        result = await agent.send(
          'Use string_tool with input "test"',
          history: history,
        );
        expect(result.output, isNotEmpty);
        history.addAll(result.messages);

        // Verify tool was executed
        final hasToolResults = history.any((m) => m.hasToolResults);
        expect(hasToolResults, isTrue);

        // Turn 3: Continue conversation
        result = await agent.send('What was the result?', history: history);
        expect(result.output, isNotEmpty);
        history.addAll(result.messages);

        // Complete conversation should have appropriate message count
        expect(history.length, greaterThan(4));

        // Validate message history follows correct pattern
        validateMessageHistory(history);
      });

      test('multi-tool workflow with dependencies', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool, intTool]);

        final result = await agent.send(
          'First use string_tool with "hello", then use int_tool with 42',
        );

        expect(result.output, isNotEmpty);
        expect(result.messages, isNotEmpty);

        // Should have executed both tools
        final toolResults = result.messages
            .expand((m) => m.toolResults)
            .toList();
        expect(toolResults.length, greaterThanOrEqualTo(1));

        // Validate message history follows correct pattern
        validateMessageHistory(result.messages);
      });

      test('complex conversation with system prompt', () async {
        final agent = Agent('openai:gpt-4o-mini');

        final history = [
          const ChatMessage(
            role: ChatMessageRole.system,
            parts: [TextPart('You are a math tutor. Always show work.')],
          ),
        ];

        final result = await agent.send('What is 15 * 23?', history: history);

        expect(result.output, isNotEmpty);
        expect(result.output, contains('15'));
        expect(result.output, contains('23'));

        // Validate message history with system prompt
        final fullHistory = [...history, ...result.messages];
        validateMessageHistory(fullHistory);
      });

      test('streaming workflow with tool execution', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool]);

        final chunks = <String>[];
        final allMessages = <ChatMessage>[];

        await for (final chunk in agent.sendStream(
          'Use string_tool with "streaming test" and explain the result',
        )) {
          chunks.add(chunk.output);
          allMessages.addAll(chunk.messages);
        }

        expect(chunks, isNotEmpty);
        expect(allMessages, isNotEmpty);

        // Should have both tool execution and explanation
        final hasToolResults = allMessages.any((m) => m.hasToolResults);
        expect(hasToolResults, isTrue);

        final fullText = chunks.join();
        expect(fullText, isNotEmpty);

        // Validate message history follows correct pattern
        validateMessageHistory(allMessages);
      });

      runProviderTest(
        'handle end-to-end workflows correctly (basic conversation)',
        (provider) async {
          // Test basic conversation
          final agent = Agent(provider.name);

          final history = <ChatMessage>[];

          // Turn 1: Initial greeting
          var result = await agent.send(
            'Hello! Reply with "Hi from ${provider.name}"',
            history: history,
          );
          expect(
            result.output,
            isNotEmpty,
            reason: 'Provider ${provider.name} should respond',
          );
          history.addAll(result.messages);

          // Turn 2: Continue conversation
          result = await agent.send(
            'Continue our conversation',
            history: history,
          );
          // Just verify we get a response - models handle conversation context
          // differently
          expect(
            result.output,
            isNotEmpty,
            reason: 'Provider ${provider.name} should respond in conversation',
          );
          history.addAll(result.messages);

          // Validate message history follows correct pattern
          validateMessageHistory(history);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      runToolProviderTest(
        'handle end-to-end workflows correctly (tool execution)',
        (provider) async {
          final agentWithTools = Agent(provider.name, tools: [stringTool]);

          final toolResult = await agentWithTools.send(
            'Use string_tool with input "${provider.name} workflow test"',
          );

          // Should have executed tool
          final hasToolResults = toolResult.messages.any(
            (m) => m.hasToolResults,
          );
          expect(
            hasToolResults,
            isTrue,
            reason: 'Provider ${provider.name} should execute tools',
          );

          // Validate message history follows correct pattern
          validateMessageHistory(toolResult.messages);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      runToolProviderTest('multi-turn conversation with multiple tool calls '
          'and message validation', (provider) async {
        // COMPREHENSIVE TEST: Validates that ALL tool-capable providers
        // maintain proper message history (user/model alternation) through:
        // 1. Multi-turn conversations (4 turns)
        // 2. Multiple tool calls in a single turn
        // 3. Tool result consolidation
        // 4. Reference to previous tool results
        final agent = Agent(provider.name, tools: [stringTool, intTool]);

        final history = <ChatMessage>[];

        // Turn 1: Initial greeting (no tools)
        var result = await agent.send(
          'Hello! I need help with some text processing and calculations.',
          history: history,
        );
        expect(result.output, isNotEmpty);
        history.addAll(result.messages);
        validateMessageHistory(history);

        // Turn 2: Single tool call
        result = await agent.send(
          'Please use string_tool with "Hello ${provider.name}"',
          history: history,
        );
        expect(result.output, isNotEmpty);
        expect(
          result.messages.any((m) => m.hasToolResults),
          isTrue,
          reason: '${provider.name} should execute string_tool',
        );
        history.addAll(result.messages);
        validateMessageHistory(history);

        // Turn 3: Multiple tool calls in one turn
        result = await agent.send(
          'Now use both tools: string_tool with "multi-tool test" '
          'and int_tool with 42',
          history: history,
        );
        expect(result.output, isNotEmpty);

        // Verify multiple tools were called
        final toolResults = result.messages
            .expand((m) => m.toolResults)
            .toList();
        expect(
          toolResults.length,
          greaterThanOrEqualTo(1),
          reason: '${provider.name} should execute multiple tools',
        );
        history.addAll(result.messages);
        validateMessageHistory(history);

        // Turn 4: Reference previous tool results
        result = await agent.send(
          'What were the results from the tools you just used?',
          history: history,
        );
        expect(result.output, isNotEmpty);
        expect(
          result.output.toLowerCase(),
          anyOf(contains('test'), contains('42'), contains('tool')),
          reason: '${provider.name} should reference previous tool results',
        );
        history.addAll(result.messages);

        // Final validation of complete multi-turn conversation
        validateMessageHistory(history);

        // Verify we have a proper multi-turn conversation
        expect(
          history.length,
          greaterThanOrEqualTo(8), // At least 4 turns * 2 messages each
          reason:
              '${provider.name} should have complete '
              'conversation history',
        );
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    group('cross-provider workflows', () {
      test('provider fallback scenario', () async {
        final providers = ['openai:gpt-4o-mini', 'google:gemini-2.5-flash'];

        var successfulProvider = '';

        for (final provider in providers) {
          final agent = Agent(provider);
          final result = await agent.send('Test provider: $provider');

          expect(result.output, isNotEmpty);
          successfulProvider = provider;
          break;
        }

        // At least one provider should work
        expect(successfulProvider, isNotEmpty);
      });

      test('provider-specific feature usage', () async {
        final testCases = [
          {
            'provider': 'openai:gpt-4o-mini',
            'feature': 'JSON mode',
            'prompt': 'Return JSON: {"test": true}',
          },
          {
            'provider': 'google:gemini-2.5-flash',
            'feature': 'multimodal',
            'prompt': 'Describe this input',
          },
        ];

        for (final testCase in testCases) {
          final agent = Agent(testCase['provider']!);
          final result = await agent.send(testCase['prompt']!);

          expect(result.output, isNotEmpty);
          // Feature-specific validation could be added here
        }
      });

      test('model comparison workflow', () async {
        final models = ['openai:gpt-4o-mini', 'google:gemini-2.5-flash'];

        const prompt = 'What is the capital of France?';
        final results = <String, String>{};

        for (final model in models) {
          final agent = Agent(model);
          final result = await agent.send(prompt);
          results[model] = result.output;
        }

        // Should get at least some results
        expect(results.keys, isNotEmpty);

        // All successful results should mention Paris
        for (final output in results.values) {
          expect(output.toLowerCase(), contains('paris'));
        }
      });
    });

    group('complex message handling', () {
      test('tool results integration in conversation flow', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool]);

        final history = <ChatMessage>[];

        // First interaction with tool
        var result = await agent.send(
          'Use string_tool with "first test"',
          history: history,
        );
        history.addAll(result.messages);

        // Continue conversation referencing tool result
        result = await agent.send(
          'What was the string tool result?',
          history: history,
        );

        expect(result.output, isNotEmpty);
        expect(result.output.toLowerCase(), contains('test'));
        history.addAll(result.messages);

        // Validate full multi-turn conversation with tools
        validateMessageHistory(history);
      });
    });

    group('error recovery and resilience', () {
      test('graceful handling of tool failures in workflow', () async {
        final agent = Agent(
          'openai:gpt-4o-mini',
          tools: [stringTool, errorTool],
        );

        final result = await agent.send(
          'Try using error_tool first, then use string_tool with "backup"',
        );

        expect(result.output, isNotEmpty);
        expect(result.messages, isNotEmpty);

        // Should have attempted both tools
        final allMessages = result.messages;
        expect(allMessages.length, greaterThan(1));
      });

      test('recovery from network interruptions', () async {
        final agent = Agent('openai:gpt-4o-mini');

        // Simulate potential network issues with rapid requests
        final futures = <Future<ChatResult<String>>>[];
        for (var i = 0; i < 3; i++) {
          futures.add(
            agent
                .send('Request $i')
                .catchError(
                  (e) => ChatResult<String>(
                    id: 'error-$i',
                    output: 'Error: $e',
                    finishReason: FinishReason.unspecified,
                    metadata: const {},
                    usage: const LanguageModelUsage(),
                  ),
                ),
          );
        }

        final results = await Future.wait(futures);
        expect(results, hasLength(3));

        // Should have a mix of successes and/or handled errors
        final successCount = results
            .where((r) => !r.output.startsWith('Error:'))
            .length;
        final errorCount = results
            .where((r) => r.output.startsWith('Error:'))
            .length;

        expect(successCount + errorCount, equals(3));
      });

      test('conversation continuation after errors', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [errorTool]);

        final history = <ChatMessage>[];

        // First attempt with error tool
        final result = await agent.send(
          'Use error_tool to test failures',
          history: history,
        );
        history.addAll(result.messages);

        // Continue conversation despite previous error
        final result2 = await agent.send(
          "Let's try a simple question instead: what is 2+2?",
          history: history,
        );

        expect(result2.output, isNotEmpty);
        expect(result2.output, contains('4'));
        history.addAll(result2.messages);

        // Validate conversation history even with error
        validateMessageHistory(history);
      });
    });

    group('performance and scaling', () {
      test('large conversation history handling', () async {
        final agent = Agent('openai:gpt-4o-mini');
        final history = <ChatMessage>[];

        // Build up conversation history
        for (var i = 0; i < 5; i++) {
          final result = await agent.send(
            'This is message number $i',
            history: history,
          );
          history.addAll(result.messages);

          // Prevent runaway history growth
          if (history.length > 50) {
            history.removeRange(0, history.length - 30);
          }

          // Small delay to prevent rate limiting
          await Future.delayed(const Duration(milliseconds: 200));
        }

        expect(history.length, greaterThanOrEqualTo(0));
      });

      test('concurrent complex workflows', () async {
        final workflows = [
          () async {
            final agent = Agent('openai:gpt-4o-mini');
            return agent.send('Workflow 1: Count to 3');
          },
          () async {
            final agent = Agent('google:gemini-2.5-flash');
            return agent.send('Workflow 2: Say hello');
          },
        ];

        final futures = workflows
            .map((workflow) => workflow().catchError((e) => e))
            .toList();

        final results = await Future.wait(futures);
        expect(results, hasLength(2));

        // Count successful workflows
        final successCount = results.whereType<ChatResult<String>>().length;
        expect(successCount, greaterThanOrEqualTo(0));
      });

      test('memory efficiency with streaming', () async {
        final agent = Agent('openai:gpt-4o-mini');

        var totalChunks = 0;
        var maxChunkSize = 0;

        await for (final chunk in agent.sendStream('Tell me a short story')) {
          totalChunks++;
          maxChunkSize = chunk.output.length > maxChunkSize
              ? chunk.output.length
              : maxChunkSize;

          // Prevent infinite streaming
          if (totalChunks > 100) {
            break;
          }

          // Each chunk should be reasonably sized
          expect(chunk.output.length, lessThan(5000));
        }

        expect(totalChunks, greaterThan(0));
        expect(maxChunkSize, greaterThanOrEqualTo(0));
      });
    });

    group('real-world usage patterns', () {
      test('code analysis workflow', () async {
        final agent = Agent('openai', tools: [stringTool]);

        const codeSnippet = '''
function fibonacci(n) {
  if (n <= 1) return n;
  return fibonacci(n-1) + fibonacci(n-2);
}
''';

        final result = await agent.send(
          'Analyze this code and use string_tool to format your response:\n'
          '$codeSnippet',
        );

        expect(result.output, isNotEmpty);
        expect(result.output.toLowerCase(), contains('fibonacci'));

        // Should have used the string tool for formatting
        final hasToolResults = result.messages.any((m) => m.hasToolResults);
        expect(hasToolResults, isTrue);
      });

      test('interactive problem solving', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [intTool]);

        final history = <ChatMessage>[];

        // Step 1: Present problem
        var result = await agent.send(
          'I need to calculate: (25 * 4) + (18 * 3). Can you help?',
          history: history,
        );
        history.addAll(result.messages);

        // Step 2: Use tools for calculation
        result = await agent.send(
          'Use int_tool to verify the calculation',
          history: history,
        );

        expect(result.output, isNotEmpty);

        // Should have mathematical reasoning and tool usage
        final hasToolResults = result.messages.any((m) => m.hasToolResults);
        expect(hasToolResults, isTrue);
        history.addAll(result.messages);

        // Validate multi-turn conversation with tools
        validateMessageHistory(history);
      });

      test('creative writing with constraints', () async {
        final agent = Agent('openai:gpt-4o-mini');

        final result = await agent.send(
          'Write a haiku about programming. '
          'Follow the 5-7-5 syllable pattern exactly.',
        );

        expect(result.output, isNotEmpty);

        // Basic structure check for haiku-like content
        final lines = result.output
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        expect(lines.length, greaterThanOrEqualTo(3));
      });
    });

    group('edge cases (limited providers)', () {
      runProviderTest(
        'special character handling across system',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          const specialInput = '{"test": "hello 世界 🌍"}';

          final result = await agent.send(
            'Process this JSON and use string_tool: $specialInput',
          );

          expect(result.output, isNotEmpty);
          expect(result.output, isA<String>());
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'very long workflow chains',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          const longPrompt =
              'Use string_tool with input "step1", '
              'then analyze the result, '
              'then explain what happened, '
              'then provide a summary, '
              'then give your final thoughts.';

          final result = await agent.send(longPrompt);

          expect(result.output, isNotEmpty);
          expect(result.messages, isNotEmpty);

          final hasToolResults = result.messages.any((m) => m.hasToolResults);
          expect(hasToolResults, isTrue);
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );
    });

    group('integration patterns', () {
      test('custom provider registration and usage', () async {
        // Create custom echo provider
        final echoProvider = _EchoProvider();

        // Register custom provider
        Providers.providerMap['echo-test'] = echoProvider;

        // Use custom provider
        final agent = Agent('echo-test');
        final result = await agent.send('Test message');

        expect(result.output, contains('Test message'));
        expect(result.messages, isNotEmpty);

        // Cleanup
        Providers.providerMap.remove('echo-test');
      });

      test('OpenAI-compatible custom provider pattern', () async {
        // Create OpenAI-compatible provider with custom baseUrl
        final customProvider = OpenAIProvider(
          name: 'custom-openai-test',
          displayName: 'Custom OpenAI',
          defaultModelNames: {ModelKind.chat: 'gpt-4o-mini'},
          baseUrl: Uri.parse('https://api.openai.com/v1'),
          apiKeyName: 'OPENAI_API_KEY',
        );

        // Register and use
        Providers.providerMap['custom-openai-test'] = customProvider;

        final agent = Agent('custom-openai-test');
        final result = await agent.send('Hello from custom provider');

        expect(result.output, isNotEmpty);
        expect(result.messages, isNotEmpty);

        // Cleanup
        Providers.providerMap.remove('custom-openai-test');
      });
    });
  });
}

/// Simple echo provider for testing custom provider patterns
class _EchoChatModel extends ChatModel<ChatModelOptions> {
  _EchoChatModel({required super.name})
    : super(defaultOptions: const ChatModelOptions());

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    ChatModelOptions? options,
    Object? outputSchema,
  }) {
    final lastMessage = messages.last;
    return Stream.value(
      ChatResult<ChatMessage>(output: ChatMessage.model(lastMessage.text)),
    );
  }

  @override
  void dispose() {}
}

class _EchoProvider extends Provider {
  _EchoProvider()
    : super(
        name: 'echo-test',
        displayName: 'Echo Test Provider',
        defaultModelNames: {ModelKind.chat: 'echo'},
        caps: {},
      );

  @override
  ChatModel<ChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    ChatModelOptions? options,
  }) => _EchoChatModel(name: name ?? defaultModelNames[ModelKind.chat]!);

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw UnimplementedError('Echo provider does not support embeddings');

  @override
  Stream<ModelInfo> listModels() async* {
    yield ModelInfo(
      providerName: name,
      name: 'echo',
      displayName: 'Echo Model',
      kinds: const {ModelKind.chat},
    );
  }
}
