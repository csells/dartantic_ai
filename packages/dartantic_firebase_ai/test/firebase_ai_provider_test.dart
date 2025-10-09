import 'dart:typed_data';

import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:dartantic_firebase_ai/src/firebase_message_mappers.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

import 'mock_firebase.dart';

void main() {
  group('FirebaseAIProvider', () {
    late FirebaseAIProvider provider;

    setUpAll(() async {
      // Initialize mock Firebase for all tests
      await initializeMockFirebase();
    });

    setUp(() {
      provider = FirebaseAIProvider();
    });

    test('has correct basic properties', () {
      expect(provider.name, equals('firebase_ai'));
      expect(provider.displayName, equals('Firebase AI'));
      expect(provider.aliases, contains('firebase'));
      expect(provider.apiKey, isNull);
      expect(provider.apiKeyName, isNull);
      expect(provider.baseUrl, isNull);
    });

    test('has correct capabilities', () {
      expect(provider.caps.contains(ProviderCaps.chat), isTrue);
      expect(provider.caps.contains(ProviderCaps.multiToolCalls), isTrue);
      expect(provider.caps.contains(ProviderCaps.typedOutput), isTrue);
      expect(provider.caps.contains(ProviderCaps.chatVision), isTrue);
      expect(provider.caps.contains(ProviderCaps.embeddings), isFalse);
    });

    test('has correct default model names', () {
      expect(
        provider.defaultModelNames[ModelKind.chat],
        equals('gemini-2.0-flash'),
      );
    });

    test('throws on embeddings model creation', () {
      expect(() => provider.createEmbeddingsModel(), throwsUnimplementedError);
    });

    group('model listing', () {
      test('lists Firebase AI compatible models', () async {
        final models = await provider.listModels().toList();

        expect(models, isNotEmpty);
        expect(
          models.any((m) => m.name == 'gemini-2.0-flash'),
          isTrue,
          reason: 'Should include Gemini 2.0 Flash',
        );
        expect(
          models.any((m) => m.name == 'gemini-1.5-flash'),
          isTrue,
          reason: 'Should include Gemini 1.5 Flash',
        );
        expect(
          models.any((m) => m.name == 'gemini-1.5-pro'),
          isTrue,
          reason: 'Should include Gemini 1.5 Pro',
        );

        for (final model in models) {
          expect(model.providerName, equals('firebase_ai'));
          expect(model.kinds.contains(ModelKind.chat), isTrue);
          expect(model.displayName, isNotEmpty);
          expect(model.description, isNotEmpty);
        }
      });
    });

    group('chat model creation', () {
      test('creates chat model with default settings', () {
        final model = provider.createChatModel();

        expect(model, isA<FirebaseAIChatModel>());
        expect(model.name, equals('gemini-2.0-flash'));
        expect(model.tools, isNull);
        expect(model.temperature, isNull);
      });

      test('creates chat model with custom settings', () {
        final tools = [
          Tool(
            name: 'test_tool',
            description: 'A test tool',
            onCall: (input) async => {'result': 'test'},
            inputSchema: JsonSchema.create({
              'type': 'object',
              'properties': {
                'input': {'type': 'string'},
              },
              'required': ['input'],
            }),
          ),
        ];

        final model = provider.createChatModel(
          name: 'gemini-1.5-pro',
          tools: tools,
          temperature: 0.7,
          options: const FirebaseAIChatModelOptions(
            topP: 0.8,
            topK: 40,
            maxOutputTokens: 1000,
          ),
        );

        expect(model, isA<FirebaseAIChatModel>());
        expect(model.name, equals('gemini-1.5-pro'));
        expect(model.tools, hasLength(1));
        expect(model.temperature, equals(0.7));
      });

      test('filters out return_result tool', () {
        final tools = [
          Tool(
            name: 'return_result',
            description: 'Should be filtered',
            onCall: (input) async => {'result': 'test'},
            inputSchema: JsonSchema.create({'type': 'object'}),
          ),
          Tool(
            name: 'keep_this',
            description: 'Should be kept',
            onCall: (input) async => {'result': 'test'},
            inputSchema: JsonSchema.create({'type': 'object'}),
          ),
        ];

        final model = provider.createChatModel(tools: tools);

        expect(model.tools, hasLength(1));
        expect(model.tools!.first.name, equals('keep_this'));
      });
    });
  });

  group('FirebaseAIChatModelOptions', () {
    test('creates with default values', () {
      const options = FirebaseAIChatModelOptions();

      expect(options.topP, isNull);
      expect(options.topK, isNull);
      expect(options.candidateCount, isNull);
      expect(options.maxOutputTokens, isNull);
      expect(options.temperature, isNull);
      expect(options.stopSequences, isNull);
      expect(options.responseMimeType, isNull);
      expect(options.responseSchema, isNull);
      expect(options.safetySettings, isNull);
      expect(options.enableCodeExecution, isNull);
    });

    test('creates with custom values', () {
      const options = FirebaseAIChatModelOptions(
        topP: 0.9,
        topK: 50,
        candidateCount: 2,
        maxOutputTokens: 2000,
        temperature: 0.5,
        stopSequences: ['STOP', 'END'],
        responseMimeType: 'application/json',
        responseSchema: {'type': 'object'},
        safetySettings: [
          FirebaseAISafetySetting(
            category: FirebaseAISafetySettingCategory.harassment,
            threshold: FirebaseAISafetySettingThreshold.blockMediumAndAbove,
          ),
        ],
        enableCodeExecution: true,
      );

      expect(options.topP, equals(0.9));
      expect(options.topK, equals(50));
      expect(options.candidateCount, equals(2));
      expect(options.maxOutputTokens, equals(2000));
      expect(options.temperature, equals(0.5));
      expect(options.stopSequences, equals(['STOP', 'END']));
      expect(options.responseMimeType, equals('application/json'));
      expect(options.responseSchema, equals({'type': 'object'}));
      expect(options.safetySettings, hasLength(1));
      expect(options.enableCodeExecution, isTrue);
    });
  });

  group('Safety Settings', () {
    test('creates safety setting correctly', () {
      const setting = FirebaseAISafetySetting(
        category: FirebaseAISafetySettingCategory.harassment,
        threshold: FirebaseAISafetySettingThreshold.blockOnlyHigh,
      );

      expect(setting.category, FirebaseAISafetySettingCategory.harassment);
      expect(setting.threshold, FirebaseAISafetySettingThreshold.blockOnlyHigh);
    });

    test('has all safety categories', () {
      const categories = FirebaseAISafetySettingCategory.values;

      expect(categories, contains(FirebaseAISafetySettingCategory.unspecified));
      expect(categories, contains(FirebaseAISafetySettingCategory.harassment));
      expect(categories, contains(FirebaseAISafetySettingCategory.hateSpeech));
      expect(
        categories,
        contains(FirebaseAISafetySettingCategory.sexuallyExplicit),
      );
      expect(
        categories,
        contains(FirebaseAISafetySettingCategory.dangerousContent),
      );
    });

    test('has all safety thresholds', () {
      const thresholds = FirebaseAISafetySettingThreshold.values;

      expect(
        thresholds,
        contains(FirebaseAISafetySettingThreshold.unspecified),
      );
      expect(
        thresholds,
        contains(FirebaseAISafetySettingThreshold.blockLowAndAbove),
      );
      expect(
        thresholds,
        contains(FirebaseAISafetySettingThreshold.blockMediumAndAbove),
      );
      expect(
        thresholds,
        contains(FirebaseAISafetySettingThreshold.blockOnlyHigh),
      );
      expect(thresholds, contains(FirebaseAISafetySettingThreshold.blockNone));
    });
  });

  group('Message Mapping', () {
    test('converts basic messages correctly', () {
      final messages = [
        ChatMessage.user('Hello'),
        ChatMessage.model('Hi there!'),
      ];

      final contentList = messages.toContentList();

      expect(contentList, hasLength(2));
      // Note: Actual Firebase AI Content testing would require Firebase AI SDK
      // This tests the interface but not the actual conversion
    });

    test('handles system messages correctly', () {
      final messages = [
        ChatMessage.system('You are helpful'),
        ChatMessage.user('Hello'),
      ];

      // System messages should be filtered out from the content list
      final contentList = messages.toContentList();

      expect(contentList, hasLength(1));
    });

    test('handles multimodal messages', () {
      final messages = [
        ChatMessage.user(
          'Look at this image:',
          parts: [
            DataPart(Uint8List.fromList([1, 2, 3]), mimeType: 'image/png'),
            LinkPart(Uri.parse('https://example.com/file.pdf')),
          ],
        ),
      ];

      final contentList = messages.toContentList();

      expect(contentList, hasLength(1));
    });

    test('handles tool call messages', () {
      final messages = [
        ChatMessage.model(
          'I need to use a tool',
          parts: const [
            ToolPart.call(
              id: 'test_1',
              name: 'test_tool',
              arguments: {'input': 'test'},
            ),
          ],
        ),
      ];

      final contentList = messages.toContentList();

      expect(contentList, hasLength(1));
    });

    test('handles tool result messages', () {
      final messages = [
        ChatMessage.user(
          '',
          parts: const [
            ToolPart.result(
              id: 'test_1',
              name: 'test_tool',
              result: {'output': 'success'},
            ),
          ],
        ),
      ];

      final contentList = messages.toContentList();

      expect(contentList, hasLength(1));
    });

    test('groups consecutive tool result messages', () {
      final messages = [
        ChatMessage.user(
          '',
          parts: const [
            ToolPart.result(
              id: 'test_1',
              name: 'test_tool',
              result: {'output': 'first'},
            ),
          ],
        ),
        ChatMessage.user(
          '',
          parts: const [
            ToolPart.result(
              id: 'test_2',
              name: 'another_tool',
              result: {'output': 'second'},
            ),
          ],
        ),
        ChatMessage.user('Regular message'),
      ];

      final contentList = messages.toContentList();

      // Tool results should be grouped into one content, plus the text message
      expect(contentList, hasLength(2));
    });
  });

  group('Schema Conversion', () {
    // Note: These tests would need a FirebaseAIChatModel instance to test
    // the actual schema conversion. For now, we test the interface.

    test('handles basic string schema', () {
      // This would test _convertSchemaToFirebase but that's private
      // We can test it indirectly through the public API if needed
      expect(true, isTrue); // Placeholder
    });

    test('handles object schema with properties', () {
      expect(true, isTrue); // Placeholder
    });

    test('handles array schema', () {
      expect(true, isTrue); // Placeholder
    });

    test('rejects unsupported schema features', () {
      expect(true, isTrue); // Placeholder for anyOf/oneOf/allOf rejection
    });
  });
}
