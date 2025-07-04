// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

// NOTE: some of these tests require environment variables to be set.
// I recommend using .vscode/settings.json like so:
//
// {
//   "dart.env": {
//     "GEMINI_API_KEY": "your_gemini_api_key",
//     "OPENAI_API_KEY": "your_openai_api_key"
//   }
// }

void main() {
  setUpAll(() {
    Logger.root.level = Level.FINE;
    Logger.root.onRecord.listen((record) {
      print('${record.level.name}: ${record.time}: ${record.message}');
    });
  });

  group('Message serialization', () {
    test('deserializes and reserializes to the same JSON structure', () {
      const jsonString = '''
[
        {
          "role": "system",
          "parts": [
            {"text": "You are a helpful AI assistant."}
          ]
        },
        {
          "role": "user",
          "parts": [
            {"text": "Hello, can you help me with a task?"}
          ]
        },
        {
          "role": "model",
          "parts": [
            {"text": "Of course! I'd be happy to help you with a task. What kind of task do you need assistance with? Please provide me with more details, and I'll do my best to help you."}
          ]
        },
        {
          "role": "user",
          "parts": [
            {"text": "Can you analyze this image and tell me what you see?"},
            {
              "name": "image.jpeg",
              "data": {
                "mimeType": "image/jpeg",
                "data": "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgab"
              }
            }
          ]
        }
      ]''';

      final inputJson = jsonDecode(jsonString);
      final messages =
          (inputJson as List).map((e) => Message.fromJson(e)).toList();
      final outputJson = messages.map((m) => m.toJson()).toList();

      // Deep equality check
      expect(outputJson, equals(inputJson));
    });

    test(
      'deserializes and reserializes link part to the same JSON structure',
      () {
        const jsonString = '''
      {
        "name": "google-logo.png",
        "url": "https://www.google.com/images/branding/googlelogo/2x/googlelogo_light_color_272x92dp.png",
        "mimeType": "image/png"
      }
      ''';
        final inputJson = jsonDecode(jsonString);
        final part = Part.fromJson(inputJson as Map<String, dynamic>);
        final outputJson = part.toJson();
        expect(outputJson, equals(inputJson));
      },
    );
  });

  group('Part naming', () {
    test('DataPart: explicit name', () {
      final part = DataPart(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        name: 'my-image.png',
      );
      expect(part.name, 'my-image.png');
    });

    test('DataPart: automatic name from image mime type', () {
      final part = DataPart(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );
      expect(part.name, 'image.jpeg');
    });

    test('DataPart: automatic name from non-image mime type', () {
      final part = DataPart(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/pdf',
      );
      expect(part.name, 'file.pdf');
    });

    test('LinkPart: explicit name', () {
      final part = LinkPart(
        Uri.parse('https://example.com/foo.bar'),
        name: 'my-file.bar',
      );
      expect(part.name, 'my-file.bar');
    });

    test('LinkPart: automatic name from url with file', () {
      final part = LinkPart(Uri.parse('https://example.com/foo.bar'));
      expect(part.name, 'foo.bar');
    });

    test('LinkPart: automatic name from url with path', () {
      final part = LinkPart(Uri.parse('https://example.com/foo/bar'));
      expect(part.name, 'bar');
    });

    test('LinkPart: automatic name from root url', () {
      final part = LinkPart(Uri.parse('https://example.com'));
      expect(part.name, '');
    });

    test('LinkPart: automatic name from url with query', () {
      final part = LinkPart(
        Uri.parse('https://example.com/image.jpg?name=test'),
      );
      expect(part.name, 'image.jpg');
    });
  });

  group('Message history and features', () {
    Future<void> testEmptyMessagesPromptIncludesUserAndModelMessages(
      Provider provider,
    ) async {
      const prompt = 'What is 2 + 2?';
      final agent = Agent.provider(provider);
      final responses = <AgentResponse>[];
      await agent
          .runStreamWithRetries(prompt, messages: [])
          .forEach(responses.add);
      final messages =
          responses.isNotEmpty ? responses.last.messages : <Message>[];

      expect(
        messages,
        isNotEmpty,
        reason: '${agent.model}: messages should not be empty',
      );

      expect(
        messages.first.role,
        MessageRole.user,
        reason: '${agent.model}: first message should be user',
      );

      expect(
        messages.first.parts.whereType<TextPart>().any((p) => p.text == prompt),
        isTrue,
        reason:
            '${agent.model}: prompt should be present in first user '
            'message',
      );
      expect(
        messages.any((m) => m.role == MessageRole.model),
        isTrue,
        reason: '${agent.model}: should contain a model response',
      );
    }

    test(
      'empty history and prompt: OpenAI',
      () =>
          testEmptyMessagesPromptIncludesUserAndModelMessages(OpenAiProvider()),
    );
    test(
      'empty history and prompt: Gemini',
      () =>
          testEmptyMessagesPromptIncludesUserAndModelMessages(GeminiProvider()),
    );

    Future<void> testMessageHistoryWithInitialMessages(
      Provider provider,
      Iterable<Message> initialMessages,
    ) async {
      final agent = Agent.provider(
        provider,
        systemPrompt:
            initialMessages.isNotEmpty &&
                    initialMessages.first.role == MessageRole.system
                ? (initialMessages.first.parts.first as TextPart).text
                : null,
      );

      final response = await agent.runWithRetries(
        'And Italy?',
        messages: initialMessages,
      );
      final messages = response.messages;

      // dump the messages to the console
      print('# ${agent.model} messages:');
      for (var i = 0; i < messages.length; i++) {
        final m = messages[i];
        print('- ${m.role}: ${m.parts.map((p) => p.toJson()).join(' | ')}');
      }

      expect(
        messages,
        isNotEmpty,
        reason: '${agent.model}: messages should not be empty',
      );
      final systemPrompt =
          initialMessages.isNotEmpty &&
                  initialMessages.first.role == MessageRole.system
              ? (initialMessages.first.parts.first as TextPart).text
              : null;
      if (systemPrompt != null) {
        expect(
          messages.first.role,
          MessageRole.system,
          reason: '${agent.model}: first message should be system',
        );
        expect(
          (messages.first.parts.first as TextPart).text,
          systemPrompt,
          reason: '${agent.model}: system prompt text should match',
        );
        expect(
          messages[1].role,
          MessageRole.user,
          reason: '${agent.model}: second message should be user',
        );
        expect(
          messages[2].role,
          MessageRole.model,
          reason: '${agent.model}: third message should be model',
        );
        expect(
          messages[3].role,
          MessageRole.user,
          reason: '${agent.model}: fourth message should be user',
        );
      } else {
        expect(
          messages.first.role,
          isNot(MessageRole.system),
          reason: '${agent.model}: no system prompt should be present',
        );
        expect(
          messages.first.role,
          MessageRole.user,
          reason:
              '${agent.model}: first message should be user '
              '(no system message)',
        );
        expect(
          messages[1].role,
          MessageRole.model,
          reason: '${agent.model}: second message should be model',
        );
        expect(
          messages[2].role,
          MessageRole.user,
          reason: '${agent.model}: third message should be user',
        );
      }
      expect(
        messages.last.role,
        MessageRole.model,
        reason:
            '${agent.model}: last message should be model '
            '(response to Italy)',
      );
      expect(
        messages.any(
          (m) => m.parts.whereType<TextPart>().any(
            (p) => p.text.contains('Italy'),
          ),
        ),
        isTrue,
        reason: '${agent.model}: should mention Italy in response',
      );
    }

    // Shared initial message lists
    final initialNoSystem = <Message>[
      Message(
        role: MessageRole.user,
        parts: [const TextPart('What is the capital of France?')],
      ),
      Message(
        role: MessageRole.model,
        parts: [const TextPart('The capital of France is Paris.')],
      ),
    ];

    final initialWithSystem = <Message>[
      Message(
        role: MessageRole.system,
        parts: [const TextPart('You are a test system prompt.')],
      ),
      ...initialNoSystem,
    ];

    test(
      'history with non-empty initial messages, with system: OpenAI',
      () => testMessageHistoryWithInitialMessages(
        OpenAiProvider(),
        initialWithSystem,
      ),
    );
    test(
      'history with non-empty initial messages, with system: Gemini',
      () async {
        await testMessageHistoryWithInitialMessages(
          GeminiProvider(),
          initialWithSystem,
        );
      },
    );
    test(
      'history with non-empty initial messages, no system: OpenAI',
      () => testMessageHistoryWithInitialMessages(
        OpenAiProvider(),
        initialNoSystem,
      ),
    );
    test(
      'history with non-empty initial messages, no system: Gemini',
      () => testMessageHistoryWithInitialMessages(
        GeminiProvider(),
        initialNoSystem,
      ),
    );

    Future<void> testSystemPromptPropagation(Provider provider) async {
      const systemPrompt = 'You are a system prompt for testing.';
      final agent = Agent.provider(provider, systemPrompt: systemPrompt);
      final responses = <AgentResponse>[];
      await agent.runStreamWithRetries('Say hello!').forEach(responses.add);
      final messages =
          responses.isNotEmpty ? responses.last.messages : <Message>[];
      if (systemPrompt.isNotEmpty) {
        expect(
          messages.isNotEmpty && messages.first.role == MessageRole.system,
          isTrue,
        );
        expect((messages.first.parts.first as TextPart).text, systemPrompt);
      } else {
        expect(
          messages.isEmpty || messages.first.role != MessageRole.system,
          isTrue,
        );
      }
    }

    test(
      'system prompt propagation: OpenAI',
      () => testSystemPromptPropagation(OpenAiProvider()),
    );
    test(
      'system prompt propagation: Gemini',
      () => testSystemPromptPropagation(GeminiProvider()),
    );

    Future<void> testTypedOutputWithHistory(Provider provider) async {
      final schema = {
        'type': 'object',
        'properties': {
          'animal': {'type': 'string'},
          'sound': {'type': 'string'},
        },
        'required': ['animal', 'sound'],
        'additionalProperties': false,
      };
      final agent = Agent.provider(
        provider,
        outputSchema: schema.toSchema(),
        outputFromJson:
            (json) => {'animal': json['animal'], 'sound': json['sound']},
      );
      final initialMessages = [
        Message(
          role: MessageRole.user,
          parts: [const TextPart('What animal says "moo"?')],
        ),
        Message(
          role: MessageRole.model,
          parts: [
            TextPart(jsonEncode({'animal': 'cow', 'sound': 'moo'})),
          ],
        ),
        Message(
          role: MessageRole.user,
          parts: [const TextPart('What animal says "quack"?')],
        ),
      ];
      final result = await agent.runForWithRetries<Map<String, dynamic>>(
        'What animal says "neigh"?',
        messages: initialMessages,
      );
      expect(result.output, isA<Map<String, dynamic>>());
      expect(result.output['animal'], isNotNull);
      expect(result.output['sound'], isNotNull);
      expect(result.output['animal'], isA<String>());
      expect(result.output['sound'], isA<String>());
    }

    test(
      'typed output with history: OpenAI',
      () => testTypedOutputWithHistory(OpenAiProvider()),
    );
    test(
      'typed output with history: Gemini',
      () => testTypedOutputWithHistory(GeminiProvider()),
    );

    Future<void> testToolCallHistory(Provider provider) async {
      final tool = Tool(
        name: 'animal_sound_lookup',
        description:
            'Maps animal sounds to animal names, or echoes any other input.',
        inputSchema:
            {
              'type': 'object',
              'properties': {
                'sound': {'type': 'string'},
              },
              'required': ['sound'],
            }.toSchema(),
        onCall: (input) async {
          final sound = input['sound'] as String;
          final animal =
              {
                'moo': 'cow',
                'quack': 'duck',
                'neigh': 'horse',
                // add more as needed
              }[sound] ??
              'unknown';
          // Echo the input regardless of whether it's a valid animal sound
          return {'animal': animal, 'sound': sound, 'echo': sound};
        },
      );
      final agent = Agent.provider(
        provider,
        tools: [tool],
        systemPrompt:
            'You MUST use the animal_sound_lookup tool for any NON-EMPTY user '
            "message, regardless of content. Pass the user's message as the "
            '"sound" parameter even if it\'s not an animal sound. This is a '
            'test of tool functionality, not animal sounds.',
      );
      final responses = <AgentResponse>[];
      await agent.runStreamWithRetries('Repeat: moo').forEach(responses.add);
      final messages =
          responses.isNotEmpty ? responses.last.messages : <Message>[];

      // Dump the messages for inspection
      print('--- Dumping messages for provider: ${agent.model} ---');
      for (var i = 0; i < messages.length; i++) {
        final m = messages[i];
        print('Message #$i: role=${m.role}, content:');
        for (final part in m.parts) {
          print('  $part');
        }
      }

      final hasToolCall = messages.any(
        (m) => m.parts.any((p) => p is ToolPart && p.kind == ToolPartKind.call),
      );
      final hasToolResult = messages.any(
        (m) =>
            m.parts.any((p) => p is ToolPart && p.kind == ToolPartKind.result),
      );
      expect(hasToolCall, isTrue, reason: 'Should include a tool call message');
      expect(
        hasToolResult,
        isTrue,
        reason: 'Should include a tool result message',
      );
      expect(
        messages.any((m) => m.role == MessageRole.model),
        isTrue,
        reason: 'Should include a model response',
      );
      expect(
        messages.any(
          (m) =>
              m.parts.whereType<TextPart>().any(
                (p) => p.text.contains('moo'),
              ) ||
              m.parts.whereType<ToolPart>().any(
                (p) =>
                    p.kind == ToolPartKind.result &&
                    p.result.toString().contains('moo'),
              ),
        ),
        isTrue,
        reason: 'Should echo the message',
      );
    }

    test(
      'tool call history: OpenAI',
      () => testToolCallHistory(OpenAiProvider()),
    );
    test(
      'tool call history: Gemini',
      () => testToolCallHistory(GeminiProvider()),
    );

    test('context is maintained across chat responses: OpenAI', () async {
      final agent = Agent.provider(
        OpenAiProvider(),
        systemPrompt: 'You are a helpful assistant.',
      );
      // First exchange
      final firstResponse = await agent.runWithRetries(
        'My favorite color is blue.',
      );
      final firstMessages = firstResponse.messages;
      // Second exchange, referencing the first
      final secondResponse = await agent.runWithRetries(
        'What color did I say I liked?',
        messages: firstMessages,
      );
      final secondOutput = secondResponse.output.toLowerCase();
      expect(secondOutput, contains('blue'));
    });
    test('context is maintained across chat responses: Gemini', () async {
      final agent = Agent.provider(
        GeminiProvider(),
        systemPrompt: 'You are a helpful assistant.',
      );
      // First exchange
      final firstResponse = await agent.runWithRetries(
        'My favorite color is blue.',
      );
      final firstMessages = firstResponse.messages;
      // Second exchange, referencing the first
      final secondResponse = await agent.runWithRetries(
        'What color did I say I liked?',
        messages: firstMessages,
      );
      final secondOutput = secondResponse.output.toLowerCase();
      expect(secondOutput, contains('blue'));
    });

    Future<void> testGrowingHistoryWithProviders(
      Iterable<Provider> providers,
      String testName,
    ) async {
      final tool = Tool(
        name: 'animal_sound_lookup',
        description: 'Maps animal sounds to animal names.',
        inputSchema:
            {
              'type': 'object',
              'properties': {
                'sound': {'type': 'string'},
              },
              'required': ['sound'],
            }.toSchema(),
        onCall: (input) async {
          print('onCall: $input');
          final sound = input['sound'] as String;
          final animal =
              {
                'moo': 'cow',
                'quack': 'duck',
                'neigh': 'horse',
                // add more as needed
              }[sound] ??
              'unknown';
          return {'animal': animal, 'sound': sound};
        },
      );
      const systemPrompt = '''
You are an assistant that must always use the provided "animal_sound_lookup" tool to answer any question about what animal makes a particular sound. 
Do not answer directly; always call the tool with the sound in question and return the tool's result to the user.
''';
      var history = <Message>[];
      var prompt = 'What animal says "moo"?';

      // Track tool call IDs across providers
      final allToolCallIds = <String>[];
      final allToolResultIds = <String>[];

      var providerIndex = 0;
      for (final provider in providers) {
        print('\n--- Provider ${providerIndex++}: ${provider.name} ---');
        print('Current history size: ${history.length} messages');

        // Debug: Print current tool call and result IDs in history
        print('Tool calls and results in history before this provider:');
        final toolCallsInHistory = <String>[];
        final toolResultsInHistory = <String>[];

        for (final msg in history) {
          for (final part in msg.parts) {
            if (part is ToolPart) {
              if (part.kind == ToolPartKind.call) {
                print('  Tool call: id=${part.id}, name=${part.name}');
                toolCallsInHistory.add(part.id);
              } else if (part.kind == ToolPartKind.result) {
                print('  Tool result: id=${part.id}, name=${part.name}');
                toolResultsInHistory.add(part.id);
              }
            }
          }
        }

        // Create agent with the current provider
        final agent = Agent.provider(
          provider,
          tools: [tool],
          systemPrompt: systemPrompt,
        );

        // Run the agent with the current history
        final result = await agent.runWithRetries(prompt, messages: history);
        print('Provider ${provider.name} output: ${result.output}');

        // Analyze tool calls and results in the new messages
        final newToolCallIds = <String>[];
        final newToolResultIds = <String>[];
        final newToolCallNames = <String, String>{};

        for (final msg in result.messages) {
          for (final part in msg.parts) {
            if (part is ToolPart) {
              if (part.kind == ToolPartKind.call) {
                print('  New tool call: id=${part.id}, name=${part.name}');
                newToolCallIds.add(part.id);
                newToolCallNames[part.id] = part.name;
                allToolCallIds.add(part.id);
              } else if (part.kind == ToolPartKind.result) {
                print('  New tool result: id=${part.id}, name=${part.name}');
                newToolResultIds.add(part.id);
                allToolResultIds.add(part.id);
              }
            }
          }
        }

        // Check for ID mismatches in the new messages
        for (final resultId in newToolResultIds) {
          if (!newToolCallIds.contains(resultId) &&
              !toolCallsInHistory.contains(resultId)) {
            print('ERROR: Tool result ID $resultId has no matching tool call!');
            print(
              'Available tool call IDs: ${newToolCallIds + toolCallsInHistory}',
            );
          }
        }

        // Update history for next provider
        history = result.messages;

        // Change the prompt for the next round
        prompt = 'What animal says "quack"?';
      }

      // Final check: verify all tool result IDs have matching tool call IDs
      print('\n--- Final verification of all tool calls and results ---');
      print('All tool call IDs: $allToolCallIds');
      print('All tool result IDs: $allToolResultIds');

      for (final resultId in allToolResultIds) {
        expect(
          allToolCallIds.contains(resultId),
          isTrue,
          reason: 'Tool result ID $resultId has no matching tool call ID',
        );
      }

      // Original checks
      expect(
        history.any(
          (m) =>
              m.parts.any((p) => p is ToolPart && p.kind == ToolPartKind.call),
        ),
        isTrue,
        reason: 'History should contain at least one tool call',
      );
      expect(
        history.any(
          (m) => m.parts.any(
            (p) => p is ToolPart && p.kind == ToolPartKind.result,
          ),
        ),
        isTrue,
        reason: 'History should contain at least one tool result',
      );
      expect(
        history.any((m) => m.role == MessageRole.system),
        isTrue,
        reason: 'History should contain a system prompt',
      );
      expect(
        history.any(
          (m) => m.parts.whereType<TextPart>().any(
            (p) => p.text.contains('moo') || p.text.contains('quack'),
          ),
        ),
        isTrue,
        reason: 'History should contain animal sounds',
      );
    }

    test('growing history Gemini→OpenAI→Gemini→OpenAI', () async {
      await testGrowingHistoryWithProviders([
        GeminiProvider(),
        OpenAiProvider(),
        GeminiProvider(),
        OpenAiProvider(),
      ], 'Gemini→OpenAI→Gemini→OpenAI');
    });

    test('growing history OpenAI→Gemini→OpenAI→Gemini', () async {
      await testGrowingHistoryWithProviders([
        OpenAiProvider(),
        GeminiProvider(),
        OpenAiProvider(),
        GeminiProvider(),
      ], 'OpenAI→Gemini→OpenAI→Gemini');
    });

    test('growing history OpenAI→OpenAI→OpenAI→OpenAI', () async {
      await testGrowingHistoryWithProviders([
        OpenAiProvider(),
        OpenAiProvider(),
        OpenAiProvider(),
        OpenAiProvider(),
      ], 'OpenAI→OpenAI→OpenAI→OpenAI');
    });

    test('growing history Gemini→Gemini→Gemini→Gemini', () async {
      await testGrowingHistoryWithProviders([
        GeminiProvider(),
        GeminiProvider(),
        GeminiProvider(),
        GeminiProvider(),
      ], 'Gemini→Gemini→Gemini→Gemini');
    });

    // use this to ensure that all new providers are history compatible
    test('growing history with all primary providers', () async {
      await testGrowingHistoryWithProviders(allProviders, 'all providers');
    });

    Future<void> testToolResultReferencedInContext(Provider provider) async {
      final tool = Tool(
        name: 'animal_sound_lookup',
        description: 'Maps animal sounds to animal names.',
        inputSchema:
            {
              'type': 'object',
              'properties': {
                'sound': {'type': 'string'},
              },
              'required': ['sound'],
            }.toSchema(),
        onCall: (input) async {
          final sound = input['sound'] as String;
          final animal =
              {
                'moo': 'cow',
                'quack': 'duck',
                'neigh': 'horse',
                // add more as needed
              }[sound] ??
              'unknown';
          return {'animal': animal, 'sound': sound};
        },
      );
      const systemPrompt = 'You are a test system prompt.';
      // Step 1: Run initial tool call
      final agent1 = Agent.provider(
        provider,
        tools: [tool],
        systemPrompt: systemPrompt,
      );
      final responses1 = await agent1.runWithRetries(
        'Echo this: magic-value-123',
      );
      final history = responses1.messages;
      // Debug: Print message history after first run
      print(
        '--- Debug: Message history after first agent run (provider: \\${agent1.model}) ---',
      );
      for (var i = 0; i < history.length; i++) {
        final m = history[i];
        print('Message #$i: role=\\${m.role}, content:');
        for (final part in m.parts) {
          print('  $part');
        }
      }
      // Step 2: Ask a follow-up referencing the tool result
      final agent2 = Agent.provider(
        provider,
        tools: [tool],
        systemPrompt: systemPrompt,
      );
      const followup = 'What value did I ask you to echo?';
      final responses2 = await agent2.runWithRetries(
        followup,
        messages: history,
      );
      final output = responses2.output;
      // Debug: Print follow-up output and message content
      print('--- Debug: Follow-up output (provider: \\${agent2.model}) ---');
      print('Follow-up prompt: \\$followup');
      print('Follow-up output: \\$output');
      final followupMessages = responses2.messages;
      print('--- Debug: Follow-up message history ---');
      for (var i = 0; i < followupMessages.length; i++) {
        final m = followupMessages[i];
        print('Message #$i: role=\\${m.role}, content:');
        for (final part in m.parts) {
          print('  $part');
        }
      }
      expect(
        output.toLowerCase(),
        contains('magic-value-123'),
        reason:
            'The agent should reference the tool result from earlier in the '
            'chat',
      );
    }

    test('tool result is referenced in later chat: Gemini', () async {
      await testToolResultReferencedInContext(GeminiProvider());
    });
    test('tool result is referenced in later chat: OpenAI', () async {
      await testToolResultReferencedInContext(OpenAiProvider());
    });
  });
}
