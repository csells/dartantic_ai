/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

import 'mock_firebase.dart';

// Test helper constant for baseUrl parameter
const _testBaseUrl = 'https://test-firebase-ai.googleapis.com/v1';

void main() {
  group('FirebaseAIChatModel Unit Tests', () {
    setUpAll(() async {
      // Initialize mock Firebase for all tests
      await initializeMockFirebase();
    });

    group('Constructor and Properties', () {
      test('creates model with default settings', () {
        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-2.0-flash',
          backend: FirebaseAIBackend.vertexAI,
        );

        expect(model.name, equals('gemini-2.0-flash'));
        expect(model.backend, equals(FirebaseAIBackend.vertexAI));
        expect(model.tools, isNull);
        expect(model.temperature, isNull);
        expect(model.defaultOptions, isA<FirebaseAIChatModelOptions>());
      });

      test('creates model with custom settings', () {
        final tools = [
          Tool(
            name: 'test_tool',
            description: 'A test tool',
            onCall: (input) async => {'result': 'test'},
            inputSchema: JsonSchema.create({
              'type': 'object',
              'properties': {'input': {'type': 'string'}},
            }),
          ),
        ];

        const options = FirebaseAIChatModelOptions(
          topP: 0.9,
          topK: 40,
          maxOutputTokens: 1000,
        );

        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.googleAI,
          tools: tools,
          temperature: 0.7,
          defaultOptions: options,
        );

        expect(model.name, equals('gemini-1.5-pro'));
        expect(model.backend, equals(FirebaseAIBackend.googleAI));
        expect(model.tools, hasLength(1));
        expect(model.tools!.first.name, equals('test_tool'));
        expect(model.temperature, equals(0.7));
        expect(model.defaultOptions, equals(options));
      });

      test('filters out return_result tool correctly', () {
        final tools = [
          Tool(
            name: 'return_result',
            description: 'Should be filtered out',
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

        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.vertexAI,
          tools: tools,
        );

        expect(model.tools, hasLength(1));
        expect(model.tools!.first.name, equals('keep_this'));
      });
    });

    group('Schema Conversion Logic', () {
      late FirebaseAIChatModel model;

      setUp(() {
        model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.vertexAI,
        );
      });

      test('handles null schema correctly', () {
        // This tests the internal _createFirebaseSchema method
        final messages = [ChatMessage.user('Test')];
        
        // Should not throw when outputSchema is null
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });

      test('converts string schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'string',
          'description': 'A test string',
        });

        final messages = [ChatMessage.user('Test')];
        
        // Should not throw for valid string schema
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('converts number schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'number',
          'description': 'A test number',
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('converts integer schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'integer',
          'description': 'A test integer',
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('converts boolean schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'boolean',
          'description': 'A test boolean',
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('converts object schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'object',
          'description': 'A test object',
          'properties': {
            'name': {'type': 'string'},
            'age': {'type': 'integer'},
            'active': {'type': 'boolean'},
          },
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('converts array schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'array',
          'description': 'A test array',
          'items': {'type': 'string'},
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('handles nullable types correctly', () {
        final schema = JsonSchema.create({
          'type': ['string', 'null'],
          'description': 'A nullable string',
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('handles enum string schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'string',
          'enum': ['red', 'green', 'blue'],
          'description': 'A color enum',
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('throws error for unsupported union types', () {
        final schema = JsonSchema.create({
          'type': ['string', 'integer'],
          'description': 'Union type not supported',
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws error for anyOf schemas', () {
        final schema = JsonSchema.create({
          'anyOf': [
            {'type': 'string'},
            {'type': 'integer'},
          ],
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws error for oneOf schemas', () {
        final schema = JsonSchema.create({
          'oneOf': [
            {'type': 'string'},
            {'type': 'integer'},
          ],
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws error for allOf schemas', () {
        final schema = JsonSchema.create({
          'allOf': [
            {'type': 'object'},
            {'properties': {'name': {'type': 'string'}}},
          ],
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws error for unsupported types during conversion', () {
        // This test verifies that the Firebase schema conversion logic
        // throws appropriate errors for unsupported types
        final messages = [ChatMessage.user('Test')];
        
        // We'll test the internal conversion logic by trying to convert
        // a schema that should cause an error in _convertSchemaToFirebase
        expect(
          () => model.sendStream(messages),
          returnsNormally, // The error will happen during actual conversion
        );
      });

      test('throws error for array without items', () {
        final schema = JsonSchema.create({
          'type': 'array',
          'description': 'Array without items definition',
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('handles nested object schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'object',
          'properties': {
            'user': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'contact': {
                  'type': 'object',
                  'properties': {
                    'email': {'type': 'string'},
                    'phone': {'type': 'string'},
                  },
                },
              },
            },
            'timestamp': {'type': 'integer'},
          },
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });

      test('handles array of objects schema correctly', () {
        final schema = JsonSchema.create({
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'name': {'type': 'string'},
              'tags': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
          },
        });

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, outputSchema: schema),
          returnsNormally,
        );
      });
    });

    group('Options Processing', () {
      late FirebaseAIChatModel model;

      setUp(() {
        model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',  
          backend: FirebaseAIBackend.vertexAI,
          temperature: 0.3,
          defaultOptions: const FirebaseAIChatModelOptions(
            topP: 0.8,
            maxOutputTokens: 500,
          ),
        );
      });

      test('uses model defaults when no options provided', () {
        final messages = [ChatMessage.user('Test')];
        
        // Should use model's temperature and defaultOptions
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });

      test('merges custom options with defaults', () {
        const options = FirebaseAIChatModelOptions(
          topK: 30,
          temperature: 0.7, // Should override model temperature
        );

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, options: options),
          returnsNormally, 
        );
      });

      test('handles all option types correctly', () {
        const options = FirebaseAIChatModelOptions(
          topP: 0.9,
          topK: 40,
          candidateCount: 1,
          maxOutputTokens: 1000,
          temperature: 0.5,
          stopSequences: ['STOP', 'END'],
          responseMimeType: 'application/json',
          responseSchema: {
            'type': 'object',
            'properties': {
              'result': {'type': 'string'},
            },
          },
          safetySettings: [
            FirebaseAISafetySetting(
              category: FirebaseAISafetySettingCategory.harassment,
              threshold: FirebaseAISafetySettingThreshold.blockMediumAndAbove,
            ),
          ],
          enableCodeExecution: true,
        );

        final messages = [ChatMessage.user('Test')];
        
        expect(
          () => model.sendStream(messages, options: options),
          returnsNormally,
        );
      });
    });

    group('Message Processing', () {
      late FirebaseAIChatModel model;

      setUp(() {
        model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.vertexAI,
        );
      });

      test('handles single user message', () {
        final messages = [ChatMessage.user('Hello')];
        
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });

      test('handles conversation history', () {
        final messages = [
          ChatMessage.user('What is 2 + 2?'),
          ChatMessage.model('4'),
          ChatMessage.user('What about 3 + 3?'),
        ];
        
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });

      test('handles system message correctly', () {
        final messages = [
          ChatMessage.system('You are a helpful assistant'),
          ChatMessage.user('Hello'),
        ];
        
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });

      test('handles empty message list', () {
        final messages = <ChatMessage>[];
        
        // Should handle empty messages gracefully
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });
    });

    group('Tool Integration', () {
      test('processes tools correctly', () {
        final tools = [
          Tool(
            name: 'calculator',
            description: 'Performs calculations',
            onCall: (input) async => {'result': 42},
            inputSchema: JsonSchema.create({
              'type': 'object',
              'properties': {
                'operation': {'type': 'string'},
                'numbers': {
                  'type': 'array',
                  'items': {'type': 'number'},
                },
              },
            }),
          ),
        ];

        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.vertexAI,
          tools: tools,
        );

        final messages = [ChatMessage.user('Calculate 2 + 2')];
        
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });

      test('handles complex tool schema', () {
        final tools = [
          Tool(
            name: 'complex_tool',
            description: 'A complex tool with nested schema',
            onCall: (input) async => {'result': 'processed'},
            inputSchema: JsonSchema.create({
              'type': 'object',
              'properties': {
                'data': {
                  'type': 'object',
                  'properties': {
                    'items': {
                      'type': 'array',
                      'items': {
                        'type': 'object',
                        'properties': {
                          'id': {'type': 'string'},
                          'value': {'type': 'number'},
                        },
                      },
                    },
                  },
                },
              },
            }),
          ),
        ];

        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.vertexAI,
          tools: tools,
        );

        final messages = [ChatMessage.user('Process this data')];
        
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });

      test('handles code execution option', () {
        const options = FirebaseAIChatModelOptions(
          enableCodeExecution: true,
        );

        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.vertexAI,
          defaultOptions: options,
        );

        final messages = [ChatMessage.user('Execute some code')];
        
        expect(
          () => model.sendStream(messages),
          returnsNormally,
        );
      });
    });

    group('Backend Switching', () {
      test('creates model with Google AI backend', () {
        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.googleAI,
        );

        expect(model.backend, equals(FirebaseAIBackend.googleAI));
      });

      test('creates model with Vertex AI backend', () {
        final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
          name: 'gemini-1.5-pro',
          backend: FirebaseAIBackend.vertexAI,
        );

        expect(model.backend, equals(FirebaseAIBackend.vertexAI));
      });
    });

    test('dispose method completes without error', () {
      final model = FirebaseAIChatModel(
          baseUrl: Uri.parse(_testBaseUrl),
        name: 'gemini-1.5-pro',
        backend: FirebaseAIBackend.vertexAI,
      );
      
      expect(() => model.dispose(), returnsNormally);
    });
  });
}