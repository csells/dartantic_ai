/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

// ignore_for_file: avoid_dynamic_calls

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

import 'test_tools.dart';
import 'test_utils.dart';

void main() {
  group('Multi-Provider Message Portability Tests', () {
    group('Group 1: Simple Message Passing', () {
      test('basic text conversation across providers', () async {
        final providers = ['google', 'anthropic', 'openai'];
        final history = <ChatMessage>[];

        // Provider 1: Initial message
        final agent1 = Agent(providers[0]);
        final result1 = await agent1.send('My name is Alice and I love hiking');
        history.addAll(result1.messages);

        // Provider 2: Continue conversation
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send('What is my name?', history: history);
        history.addAll(result2.messages);
        expect(result2.output.toLowerCase(), contains('alice'));

        // Provider 3: Further continuation
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'What do I love doing?',
          history: history,
        );
        history.addAll(result3.messages);
        expect(result3.output.toLowerCase(), contains('hiking'));

        validateMessageHistory(history);
      });

      test('system prompt preservation across providers', () async {
        final systemMessage = ChatMessage.system(
          'You are a helpful pirate who always speaks in pirate language.',
        );
        final providers = ['openai', 'google', 'anthropic'];
        final history = <ChatMessage>[systemMessage];

        // Provider 1 with system prompt
        final agent1 = Agent(providers[0]);
        final result1 = await agent1.send('Hello there!', history: history);
        history.addAll(result1.messages);
        expect(
          result1.output.toLowerCase(),
          anyOf(contains('ahoy'), contains('matey'), contains('arr')),
        );

        // Provider 2 continues with same context
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'Tell me about treasure',
          history: history,
        );
        history.addAll(result2.messages);
        expect(
          result2.output.toLowerCase(),
          anyOf(contains('treasure'), contains('gold'), contains('booty')),
        );

        // Provider 3 verifies system prompt still applies
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'How do you say goodbye?',
          history: history,
        );
        history.addAll(result3.messages);
        expect(
          result3.output.toLowerCase(),
          anyOf(contains('fare'), contains('ahoy'), contains('sail')),
        );

        validateMessageHistory(history);
      });

      test('round-robin conversation pattern', () async {
        final providers = ['anthropic', 'openai', 'google'];
        final history = <ChatMessage>[];

        // Round 1
        for (var i = 0; i < providers.length; i++) {
          final agent = Agent(providers[i]);
          final prompt = i == 0
              ? 'I have a pet dog named Max who is 5 years old'
              : i == 1
              ? 'How old is my pet?'
              : 'What kind of animal is Max?';

          final result = await agent.send(prompt, history: history);
          history.addAll(result.messages);

          if (i > 0) {
            expect(result.output.toLowerCase(), contains(i == 1 ? '5' : 'dog'));
          }
        }

        validateMessageHistory(history);
      });
    });

    group('Group 2: Tool Call Message Portability', () {
      test('single tool call across providers', () async {
        final providers = ['google', 'anthropic', 'openai'];
        final history = <ChatMessage>[];
        final tools = <Tool>[weatherTool];

        // Provider 1: Call weather tool
        final agent1 = Agent(providers[0], tools: tools);
        final result1 = await agent1.send(
          'What is the weather in Boston?',
          history: history,
        );
        history.addAll(result1.messages);

        // Verify tool was called
        final toolCallMessages = result1.messages.where(
          (m) => m.role == ChatMessageRole.model && m.hasToolCalls,
        );
        expect(toolCallMessages, isNotEmpty);

        // Provider 2: Reference the weather result
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'Based on the weather I just looked up, should I bring a jacket?',
          history: history,
        );
        history.addAll(result2.messages);
        expect(
          result2.output.toLowerCase(),
          anyOf(
            contains('weather'),
            contains('temperature'),
            contains('boston'),
          ),
        );

        // Provider 3: Ask follow-up
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'What city did we check the weather for?',
          history: history,
        );
        history.addAll(result3.messages);
        expect(result3.output.toLowerCase(), contains('boston'));

        validateMessageHistory(history);
      });

      test('multiple tool calls in one turn', () async {
        final providers = ['openai', 'google', 'anthropic'];
        final history = <ChatMessage>[];
        final tools = <Tool>[weatherTool, temperatureTool];

        // Provider 1: Call multiple tools
        final agent1 = Agent(providers[0], tools: tools);
        final result1 = await agent1.send(
          'Get me the weather in Seattle and the temperature in Chicago',
          history: history,
        );
        history.addAll(result1.messages);

        // Verify multiple tools were called
        final toolCalls = result1.messages
            .where((m) => m.role == ChatMessageRole.model)
            .expand((m) => m.toolCalls)
            .toList();
        expect(toolCalls.length, greaterThanOrEqualTo(2));

        // Provider 2: Synthesize results
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'Compare the weather conditions between the two cities I just '
          'checked',
          history: history,
        );
        history.addAll(result2.messages);
        expect(
          result2.output.toLowerCase(),
          allOf(contains('seattle'), contains('chicago')),
        );

        // Provider 3: Ask comparison
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'Which city had better weather?',
          history: history,
        );
        history.addAll(result3.messages);
        expect(
          result3.output.toLowerCase(),
          anyOf(contains('seattle'), contains('chicago')),
        );

        validateMessageHistory(history);
      });

      test('sequential tool dependencies', () async {
        final providers = ['anthropic', 'openai', 'google'];
        final history = <ChatMessage>[];

        // Provider 1: Call first tool
        final agent1 = Agent(providers[0], tools: <Tool>[multiStepTool1]);
        final result1 = await agent1.send(
          'Use step1 tool with input "hello world"',
          history: history,
        );
        history.addAll(result1.messages);

        // Provider 2: Use result for second tool
        final agent2 = Agent(providers[1], tools: <Tool>[multiStepTool2]);
        final result2 = await agent2.send(
          'Now use step2 tool with the result from step1',
          history: history,
        );
        history.addAll(result2.messages);

        // Provider 3: Summarize workflow
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'Summarize what we did with the two step process',
          history: history,
        );
        history.addAll(result3.messages);
        expect(
          result3.output.toLowerCase(),
          allOf(contains('step'), anyOf(contains('1'), contains('2'))),
        );

        validateMessageHistory(history);
      });

      test('tool error handling across providers', () async {
        final providers = ['google', 'openai', 'anthropic'];
        final history = <ChatMessage>[];

        // Provider 1: Call tool that might fail
        final agent1 = Agent(providers[0], tools: <Tool>[weatherTool]);
        final result1 = await agent1.send(
          'Check the weather in Boston',
          history: history,
        );
        history.addAll(result1.messages);

        // Provider 2: Reference the result
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'What was the weather result?',
          history: history,
        );
        history.addAll(result2.messages);

        // Provider 3: Continue conversation
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'Should we check another city?',
          history: history,
        );
        history.addAll(result3.messages);

        validateMessageHistory(history);
      });
    });

    group('Group 3: Complex Conversations', () {
      test('multi-turn with mixed content', () async {
        final providers = ['openai', 'anthropic', 'google'];
        final tools = <Tool>[weatherTool, temperatureTool];
        final history = <ChatMessage>[];
        var providerIndex = 0;

        // Turn 1: Simple text
        var agent = Agent(providers[providerIndex % 3]);
        var result = await agent.send(
          'My name is Bob and I live in Seattle',
          history: history,
        );
        history.addAll(result.messages);
        providerIndex++;

        // Turn 2: Ask about name
        agent = Agent(providers[providerIndex % 3]);
        result = await agent.send('What is my name?', history: history);
        history.addAll(result.messages);
        expect(result.output.toLowerCase(), contains('bob'));
        providerIndex++;

        // Turn 3: Tool call
        agent = Agent(providers[providerIndex % 3], tools: tools);
        result = await agent.send(
          'Check the weather where I live',
          history: history,
        );
        history.addAll(result.messages);
        providerIndex++;

        // Turn 4: Reference tool result
        agent = Agent(providers[providerIndex % 3]);
        result = await agent.send(
          'Is it good weather for a walk?',
          history: history,
        );
        history.addAll(result.messages);
        providerIndex++;

        // Turn 5: Another tool call
        agent = Agent(providers[providerIndex % 3], tools: tools);
        result = await agent.send(
          'Also check the temperature in New York',
          history: history,
        );
        history.addAll(result.messages);
        providerIndex++;

        // Turn 6: Synthesize everything
        agent = Agent(providers[providerIndex % 3]);
        result = await agent.send(
          'Summarize everything we discussed: my name, where I live, and the '
          'weather info',
          history: history,
        );
        history.addAll(result.messages);
        expect(
          result.output.toLowerCase(),
          allOf(
            contains('bob'),
            contains('seattle'),
            anyOf(contains('weather'), contains('temperature')),
          ),
        );

        validateMessageHistory(history);
      });

      test('tool result references across providers', () async {
        final providers = ['google', 'openai', 'anthropic'];
        final tools = <Tool>[
          weatherTool,
          distanceCalculatorTool,
          stockPriceTool,
        ];
        final history = <ChatMessage>[];

        // Provider 1: Multiple tool calls
        final agent1 = Agent(providers[0], tools: tools);
        final result1 = await agent1.send(
          'Check the weather in Boston, calculate distance from Boston to '
          'Seattle, and get Apple stock price',
          history: history,
        );
        history.addAll(result1.messages);

        // Provider 2: Reference specific results
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'Based on the distance calculation, how long would it take to drive '
          'between those cities at 60 mph?',
          history: history,
        );
        history.addAll(result2.messages);
        expect(
          result2.output.toLowerCase(),
          anyOf(contains('hour'), contains('time'), contains('drive')),
        );

        // Provider 3: Compare results
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'If Apple stock costs what we just looked up, how many shares could '
          r'I buy with $10,000?',
          history: history,
        );
        history.addAll(result3.messages);
        expect(
          result3.output.toLowerCase(),
          anyOf(contains('share'), contains('stock'), contains('buy')),
        );

        validateMessageHistory(history);
      });

      test('streaming conversation across providers', () async {
        final providers = ['anthropic', 'google', 'openai'];
        final history = <ChatMessage>[];

        // Provider 1: Stream initial message
        final agent1 = Agent(providers[0]);
        final chunks1 = <String>[];
        await for (final chunk in agent1.sendStream(
          'I enjoy programming in Dart and Flutter',
        )) {
          chunks1.add(chunk.output);
          history.addAll(chunk.messages);
        }
        expect(chunks1.join(), isNotEmpty);

        // Provider 2: Stream follow-up
        final agent2 = Agent(providers[1]);
        final chunks2 = <String>[];
        await for (final chunk in agent2.sendStream(
          'What programming language did I mention?',
          history: history,
        )) {
          chunks2.add(chunk.output);
          history.addAll(chunk.messages);
        }
        final response2 = chunks2.join().toLowerCase();
        expect(response2, contains('dart'));

        // Provider 3: Stream final question
        final agent3 = Agent(providers[2]);
        final chunks3 = <String>[];
        await for (final chunk in agent3.sendStream(
          'What framework did I mention alongside the language?',
          history: history,
        )) {
          chunks3.add(chunk.output);
          history.addAll(chunk.messages);
        }
        final response3 = chunks3.join().toLowerCase();
        expect(response3, contains('flutter'));

        validateMessageHistory(history);
      });
    });

    group('Group 4: Typed Output Portability', () {
      test('basic typed output across providers', () async {
        final providers = ['openai', 'google', 'anthropic'];
        final history = <ChatMessage>[];

        final citySchema = JsonSchema.create({
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
            'country': {'type': 'string'},
            'population': {'type': 'integer'},
          },
          'required': ['city', 'country'],
        });

        // Provider 1: Generate JSON
        final agent1 = Agent(providers[0]);
        final result1 = await agent1.sendFor<Map<String, dynamic>>(
          'Tell me about Tokyo in the specified format',
          outputSchema: citySchema,
        );
        history.addAll(result1.messages);
        expect(result1.output['city'], equals('Tokyo'));

        // Provider 2: Reference the JSON
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'What country is the city from the previous response located in?',
          history: history,
        );
        history.addAll(result2.messages);
        expect(result2.output.toLowerCase(), contains('japan'));

        // Provider 3: Ask about specific field
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'Did the previous city data include population information?',
          history: history,
        );
        history.addAll(result3.messages);

        validateMessageHistory(history);
      });

      test(
        'recipe scenario with typed output - anthropic and openai',
        () async {
          final providers = ['anthropic', 'openai'];
          final history = <ChatMessage>[];

          final recipeSchema = JsonSchema.create({
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'ingredients': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'instructions': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'prep_time': {'type': 'string'},
              'cook_time': {'type': 'string'},
              'servings': {'type': 'integer'},
            },
            'required': [
              'name',
              'ingredients',
              'instructions',
              'prep_time',
              'cook_time',
              'servings',
            ],
          });

          // Provider 1: Look up recipe with tool + typed output
          final agent1 = Agent(providers[0], tools: <Tool>[recipeLookupTool]);
          final result1 = await agent1.sendFor<Map<String, dynamic>>(
            "Can you show me grandma's mushroom omelette recipe?",
            history: [ChatMessage.system('You are an expert chef.')],
            outputSchema: recipeSchema,
          );
          history.addAll(result1.messages);
          expect(result1.output['name'], contains('Mushroom'));
          expect(result1.output['ingredients'], isList);

          // Provider 2: Modify recipe with typed output
          final agent2 = Agent(providers[1]);
          final result2 = await agent2.sendFor<Map<String, dynamic>>(
            'Can you modify the recipe to use spinach instead of mushrooms?',
            history: history,
            outputSchema: recipeSchema,
          );
          history.addAll(result2.messages);
          expect(result2.output['name'], contains('Spinach'));
          expect(
            result2.output['ingredients'].any(
              (i) => i.toString().toLowerCase().contains('spinach'),
            ),
            isTrue,
          );
          expect(
            result2.output['ingredients'].any(
              (i) => i.toString().toLowerCase().contains('mushroom'),
            ),
            isFalse,
          );

          validateMessageHistory(history);
        },
      );

      test('typed output with tools streaming - openai and google', () async {
        final providers = ['openai', 'google'];
        final history = <ChatMessage>[];
        final tools = <Tool>[temperatureTool, currentDateTimeTool];

        final weatherReportSchema = JsonSchema.create({
          'type': 'object',
          'properties': {
            'location': {'type': 'string'},
            'temperature': {'type': 'string'},
            'timestamp': {'type': 'string'},
            'summary': {'type': 'string'},
          },
          'required': ['location', 'temperature', 'timestamp', 'summary'],
        });

        // Provider 1: Get weather data with tools and stream typed output
        final agent1 = Agent(providers[0], tools: tools);

        final chunks1 = <String>[];
        final messages1 = <ChatMessage>[];
        await for (final chunk in agent1.sendStream(
          'Get the current temperature in Paris and create a weather report',
          outputSchema: weatherReportSchema,
        )) {
          chunks1.add(chunk.output);
          messages1.addAll(chunk.messages);
        }
        history.addAll(messages1);

        // Provider 2: Reference the streamed data
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'What location was mentioned in the weather report?',
          history: history,
        );
        history.addAll(result2.messages);
        expect(result2.output.toLowerCase(), contains('paris'));

        validateMessageHistory(history);
      });

      test('complex nested schema portability', () async {
        final providers = ['google', 'anthropic', 'openai'];
        final history = <ChatMessage>[];

        final companySchema = JsonSchema.create({
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'founded': {'type': 'integer'},
            'headquarters': {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
                'country': {'type': 'string'},
                'address': {'type': 'string'},
              },
              'required': ['city', 'country'],
            },
            'products': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                  'category': {'type': 'string'},
                },
                'required': ['name', 'category'],
              },
            },
          },
          'required': ['name', 'founded', 'headquarters', 'products'],
        });

        // Provider 1: Generate complex nested data
        final agent1 = Agent(providers[0]);
        final result1 = await agent1.sendFor<Map<String, dynamic>>(
          'Tell me about Apple Inc. in the specified format',
          outputSchema: companySchema,
        );
        history.addAll(result1.messages);
        expect(result1.output['name'], contains('Apple'));
        expect(result1.output['headquarters'], isMap);
        expect(result1.output['products'], isList);

        // Provider 2: Query nested data
        final agent2 = Agent(providers[1]);
        final result2 = await agent2.send(
          'What city is the company headquarters located in?',
          history: history,
        );
        history.addAll(result2.messages);
        expect(
          result2.output.toLowerCase(),
          anyOf(contains('cupertino'), contains('california')),
        );

        // Provider 3: Query array data
        final agent3 = Agent(providers[2]);
        final result3 = await agent3.send(
          'Name one product from the company data',
          history: history,
        );
        history.addAll(result3.messages);
        expect(
          result3.output.toLowerCase(),
          anyOf(
            contains('iphone'),
            contains('ipad'),
            contains('mac'),
            contains('apple'),
          ),
        );

        validateMessageHistory(history);
      });
    });
  });
}
