import 'dart:typed_data';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

void main() {
  group('Chat', () {
    late Agent agent;

    setUp(() {
      // Use a real Agent with OpenAI for testing
      agent = Agent('openai:gpt-4o-mini');
    });

    test('should initialize with empty history', () {
      final chat = Chat(agent);

      expect(chat.agent, equals(agent));
      expect(chat.history, isEmpty);
    });

    test('should initialize with provided history', () {
      final initialHistory = [
        ChatMessage.user('Hello'),
        ChatMessage.model('Hi there!'),
      ];
      final chat = Chat(agent, history: initialHistory);

      expect(chat.history.length, equals(2));
      expect(chat.history[0].text, equals('Hello'));
      expect(chat.history[1].text, equals('Hi there!'));
    });

    test('should send message and update history', () async {
      final chat = Chat(agent);

      final result = await chat.send('Say "Hello!" and nothing else');

      expect(result.output.toLowerCase(), contains('hello'));
      expect(chat.history.length, equals(2));
      expect(chat.history[0].role, equals(ChatMessageRole.user));
      expect(chat.history[0].text, equals('Say "Hello!" and nothing else'));
      expect(chat.history[1].role, equals(ChatMessageRole.model));
      expect(chat.history[1].text, isNotEmpty);
    });

    test(
      'should maintain conversation history across multiple turns',
      () async {
        final chat = Chat(agent);

        // Turn 1
        await chat.send('My name is Alice. Just acknowledge this.');
        expect(chat.history.length, equals(2));

        // Turn 2 - should remember the name
        final result = await chat.send('What is my name?');
        expect(chat.history.length, equals(4));
        expect(result.output.toLowerCase(), contains('alice'));
      },
    );

    test('should send message with attachments', () async {
      final chat = Chat(agent);

      // Create a data attachment instead of text to avoid TextPart conflict
      final attachment = DataPart(
        Uint8List.fromList('The sky is blue.'.codeUnits),
        mimeType: 'text/plain',
      );

      final result = await chat.send(
        'What does the text attachment say about the sky?',
        attachments: [attachment],
      );

      expect(result.output.toLowerCase(), contains('blue'));
      expect(chat.history.length, equals(2));
    });

    test('should send message with output schema', () async {
      final chat = Chat(agent);

      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'number'},
        },
        'required': ['name', 'age'],
      });

      final result = await chat.send(
        'Return a JSON object with name "John" and age 30',
        outputSchema: schema,
      );

      expect(result.output, contains('John'));
      expect(result.output, contains('30'));
      expect(chat.history.length, equals(2));
    });

    test('should send typed message with sendFor', () async {
      final chat = Chat(agent);

      final result = await chat.sendFor<TestTownAndCountry>(
        'Return London, England as the town and country',
        outputSchema: JsonSchema.create(TestTownAndCountry.schemaMap),
        outputFromJson: TestTownAndCountry.fromJson,
      );

      expect(result.output.town, equals('London'));
      expect(result.output.country, equals('England'));
      expect(chat.history.length, equals(2));
    });

    test('should stream messages and update history', () async {
      final chat = Chat(agent);

      final chunks = <String>[];
      await for (final chunk in chat.sendStream(
        'Say "Hello world" and nothing else',
      )) {
        chunks.add(chunk.output);
      }

      final fullResponse = chunks.join();
      expect(fullResponse.toLowerCase(), contains('hello'));
      expect(fullResponse.toLowerCase(), contains('world'));
      expect(chat.history.length, equals(2));
      expect(
        chat.history[0].text,
        equals('Say "Hello world" and nothing else'),
      );
      expect(chat.history[1].text, isNotEmpty);
    });

    test('should preserve message metadata and usage', () async {
      final chat = Chat(agent);

      final result = await chat.send('Say "Hi"');

      // Usage information may not always be available depending on the model
      final usage = result.usage;
      if (usage != null) {
        // If usage is provided, check the tokens if they are available
        final promptTokens = usage.promptTokens;
        if (promptTokens != null) {
          expect(promptTokens, greaterThan(0));
        }
        final responseTokens = usage.responseTokens;
        if (responseTokens != null) {
          expect(responseTokens, greaterThan(0));
        }
      }
      // Finish reason should be either stop or unspecified
      expect(
        result.finishReason,
        anyOf(equals(FinishReason.stop), equals(FinishReason.unspecified)),
      );
    });

    test('should work with tools', () async {
      // Create agent with tools
      final agentWithTools = Agent(
        'openai:gpt-4o-mini',
        tools: [testWeatherTool],
      );

      final chat = Chat(agentWithTools);

      final result = await chat.send('What is the weather in Paris?');

      // Should have called the weather tool
      expect(result.output.toLowerCase(), contains('paris'));
      expect(result.output, matches(RegExp(r'\d+'))); // Contains temperature

      // History should include tool calls
      expect(chat.history.length, greaterThanOrEqualTo(2));
    });

    test('should handle typed output with custom types', () async {
      final chat = Chat(agent);

      final result = await chat.sendFor<TestTimeAndTemperature>(
        'Return the current time as 2024-01-15T10:30:00Z and temperature '
        'as 22.5',
        outputSchema: TestTimeAndTemperature.schema,
        outputFromJson: TestTimeAndTemperature.fromJson,
      );

      expect(result.output.time.year, equals(2024));
      expect(result.output.time.month, equals(1));
      expect(result.output.time.day, equals(15));
      expect(result.output.temperature, equals(22.5));
      expect(chat.history.length, equals(2));
    });
  });
}

// Test types for typed output tests
class TestTownAndCountry {
  const TestTownAndCountry({required this.town, required this.country});

  factory TestTownAndCountry.fromJson(Map<String, dynamic> json) =>
      TestTownAndCountry(
        town: json['town'] as String,
        country: json['country'] as String,
      );

  final String town;
  final String country;

  static final schemaMap = {
    'type': 'object',
    'properties': {
      'town': {'type': 'string'},
      'country': {'type': 'string'},
    },
    'required': ['town', 'country'],
  };
}

class TestTimeAndTemperature {
  const TestTimeAndTemperature({required this.time, required this.temperature});

  factory TestTimeAndTemperature.fromJson(Map<String, dynamic> json) =>
      TestTimeAndTemperature(
        time: DateTime.parse(json['time'] as String),
        temperature: (json['temperature'] as num).toDouble(),
      );

  static final schema = JsonSchema.create({
    'type': 'object',
    'properties': {
      'time': {'type': 'string'},
      'temperature': {'type': 'number'},
    },
    'required': ['time', 'temperature'],
  });

  final DateTime time;
  final double temperature;
}

// Test tool for weather
final testWeatherTool = Tool<Map<String, dynamic>>(
  name: 'weather',
  description: 'Get the weather for a given location',
  inputSchema: JsonSchema.create({
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description': 'The location to get the weather for',
      },
    },
    'required': ['location'],
  }),
  onCall: (input) {
    final location = input['location'] as String;
    return {
      'location': location,
      'temperature': 22,
      'unit': 'C',
      'conditions': 'sunny',
    };
  },
);
