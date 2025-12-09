// CRITICAL TEST FAILURE INVESTIGATION PROCESS: When a test fails for a provider
// capability:
// 1. NEVER immediately disable the capability in provider definitions
// 2. ALWAYS investigate at the API level first:
//    - Test with curl to verify if the feature works at the raw API level
//    - Check the provider's official documentation
//    - Look for differences between our implementation and the API requirements
// 3. ONLY disable a capability after confirming:
//    - The API itself doesn't support the feature, OR
//    - The API has a fundamental limitation (like Together's streaming tool
//      format)
// 4. If the API supports it but our code doesn't: FIX THE IMPLEMENTATION
// 5. LET EXCEPTIONS BUBBLE UP: Do not add defensive checks or try-catch blocks.
//    Missing API keys, network errors, and provider issues should fail loudly
//    so they can be identified and fixed immediately.

// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart' as js;
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  // Recipe lookup tool for chef scenario
  final recipeLookupTool = Tool<Map<String, dynamic>>(
    name: 'lookup_recipe',
    description: 'Look up a recipe by name',
    inputSchema: js.JsonSchema.create({
      'type': 'object',
      'properties': {
        'recipe_name': {
          'type': 'string',
          'description': 'The name of the recipe to look up',
        },
      },
      'required': ['recipe_name'],
    }),

    onCall: (input) {
      final recipeName = input['recipe_name'] as String;
      // Mock recipe database
      if (recipeName.toLowerCase().contains('mushroom') &&
          recipeName.toLowerCase().contains('omelette')) {
        return {
          'name': "Grandma's Mushroom Omelette",
          'ingredients': [
            '3 large eggs',
            '1/4 cup sliced mushrooms',
            '2 tablespoons butter',
            '1/4 cup shredded cheddar cheese',
            'Salt and pepper to taste',
            '1 tablespoon fresh chives',
          ],
          'instructions': [
            'Beat eggs in a bowl with salt and pepper',
            'Heat butter in a non-stick pan over medium heat',
            'Sauté mushrooms until golden, about 3 minutes',
            'Pour beaten eggs over mushrooms',
            'When eggs begin to set, sprinkle cheese on one half',
            'Fold omelette in half and cook until cheese melts',
            'Garnish with fresh chives and serve',
          ],
          'prep_time': '5 minutes',
          'cook_time': '10 minutes',
          'servings': 1,
        };
      }
      return {
        'error': 'Recipe not found',
        'suggestion': 'Try searching for "mushroom omelette"',
      };
    },
  );

  // Recipe schema for chef scenario
  final recipeSchema = js.JsonSchema.create({
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

  // Tool for iterative test - returns a secret code
  final getSecretCodeTool = Tool<Map<String, dynamic>>(
    name: 'get_secret_code',
    description: 'Gets a secret code that must be validated',
    inputSchema: js.JsonSchema.create({'type': 'object', 'properties': {}}),
    onCall: (input) => {
      'code': 'SECRET-XYZ-789',
      'issued_at': '2025-01-09T12:00:00Z',
    },
  );

  // Tool for iterative test - validates the code from first tool
  final validateCodeTool = Tool<Map<String, dynamic>>(
    name: 'validate_code',
    description: 'Validates a secret code and returns validation details',
    inputSchema: js.JsonSchema.create({
      'type': 'object',
      'properties': {
        'code': {'type': 'string', 'description': 'The code to validate'},
      },
      'required': ['code'],
    }),
    onCall: (input) {
      final code = input['code'] as String;
      final isValid = code == 'SECRET-XYZ-789';
      return {
        'valid': isValid,
        'code': code,
        'message': isValid
            ? 'Code is valid and authorized'
            : 'Invalid code provided',
        'access_level': isValid ? 'admin' : 'none',
        'expires_at': '2025-12-31T23:59:59Z',
      };
    },
  );

  // Schema for validation result
  final validationResultSchema = js.JsonSchema.create({
    'type': 'object',
    'properties': {
      'code': {'type': 'string'},
      'valid': {'type': 'boolean'},
      'message': {'type': 'string'},
      'access_level': {'type': 'string'},
      'expires_at': {'type': 'string'},
    },
    'required': ['code', 'valid', 'message', 'access_level', 'expires_at'],
  });

  group('typed output with tools', () {
    group('iterative tool calls with typed output', () {
      // Tests that orchestrators properly support iterative tool calling with
      // typed output. The model needs to:
      // 1. Call get_secret_code to get the code
      // 2. Call validate_code with that code
      // 3. Return typed JSON output
      //
      // This verifies that orchestrators loop through tool execution until the
      // model has no more tool calls, then generate the final typed output.
      runProviderTest(
        'sequential tool calls then typed output',
        (provider) async {
          final agent = Agent(
            provider.name,
            tools: [getSecretCodeTool, validateCodeTool],
          );

          final chunks = <String>[];
          final messages = <ChatMessage>[];

          await for (final chunk in agent.sendStream(
            'First call get_secret_code to retrieve the code. Then call '
            'validate_code with that code. Finally, return the validation '
            'result matching the schema',
            outputSchema: validationResultSchema,
          )) {
            if (chunk.output.isNotEmpty) {
              chunks.add(chunk.output);
            }
            messages.addAll(chunk.messages);
          }

          // Verify both tools were called
          final toolCalls = messages
              .where((m) => m.role == ChatMessageRole.model)
              .expand((m) => m.parts)
              .whereType<ToolPart>()
              .where((p) => p.kind == ToolPartKind.call)
              .toList();

          // Should have called BOTH tools sequentially
          expect(
            toolCalls.length,
            greaterThanOrEqualTo(2),
            reason: 'Should call get_secret_code then validate_code',
          );
          expect(
            toolCalls.any((t) => t.name == 'get_secret_code'),
            isTrue,
            reason: 'Should call get_secret_code',
          );
          expect(
            toolCalls.any((t) => t.name == 'validate_code'),
            isTrue,
            reason: 'Should call validate_code with the retrieved code',
          );

          // Verify typed output
          final output = chunks.join();
          final json = jsonDecode(output) as Map<String, dynamic>;
          expect(json['code'], equals('SECRET-XYZ-789'));
          expect(json['valid'], isTrue);
          expect(json['message'], contains('valid'));
          expect(json['access_level'], equals('admin'));
        },
        requiredCaps: {ProviderTestCaps.typedOutputWithTools},
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });

    group('multi-turn chat with typed output and tools (streaming)', () {
      runProviderTest(
        'chef conversation with streaming',
        (provider) async {
          final agent = Agent(provider.name, tools: [recipeLookupTool]);

          // First turn: Look up the recipe using streaming
          final firstChunks = <String>[];
          final firstMessages = <ChatMessage>[
            ChatMessage.system(
              'You are a chef assistant with access to a recipe database. '
              'When users ask for recipes, you MUST use the lookup_recipe tool '
              'to retrieve the exact recipe from the database. Never invent '
              'recipes - always look them up first.',
            ),
          ];

          await for (final chunk in agent.sendStream(
            "Please look up grandma's mushroom omelette recipe "
            'from the database.',
            history: firstMessages,
            outputSchema: recipeSchema,
          )) {
            if (chunk.output.isNotEmpty) {
              firstChunks.add(chunk.output);
            }
            firstMessages.addAll(chunk.messages);
          }

          // Verify first response
          final firstOutput = firstChunks.join();
          final firstJson = jsonDecode(firstOutput) as Map<String, dynamic>;
          expect(firstJson['name'], contains('Mushroom Omelette'));
          expect(firstJson['ingredients'], isA<List>());
          expect(firstJson['ingredients'], isNotEmpty);
          expect(
            (firstJson['ingredients'] as List).join(' ').toLowerCase(),
            contains('mushroom'),
          );

          // Verify lookup_recipe tool was called (return_result may also be
          // present for typed output)
          final toolCalls = firstMessages
              .where((m) => m.role == ChatMessageRole.model)
              .expand((m) => m.parts)
              .whereType<ToolPart>()
              .where((p) => p.kind == ToolPartKind.call)
              .toList();
          expect(toolCalls, isNotEmpty);
          expect(
            toolCalls.any((t) => t.name == 'lookup_recipe'),
            isTrue,
            reason: 'Should have called lookup_recipe tool',
          );

          // Second turn: Modify the recipe using streaming
          final secondChunks = <String>[];
          final secondMessages = <ChatMessage>[];

          await for (final chunk in agent.sendStream(
            'update it to replace the mushrooms with ham '
            'Ensure the title, ingredients and instructions '
            'reflect this change.',
            history: firstMessages,
            outputSchema: recipeSchema,
          )) {
            if (chunk.output.isNotEmpty) {
              secondChunks.add(chunk.output);
            }
            secondMessages.addAll(chunk.messages);
          }

          // Verify second response
          final secondOutput = secondChunks.join();
          final secondJson = jsonDecode(secondOutput) as Map<String, dynamic>;
          expect(secondJson['name'].toLowerCase(), contains('ham'));
          expect(
            (secondJson['ingredients'] as List).join(' ').toLowerCase(),
            isNot(contains('mushroom')),
          );
          expect(secondJson['ingredients'], anyElement(contains('ham')));
          // Instructions should be updated too
          expect(
            (secondJson['instructions'] as List).join(' ').toLowerCase(),
            isNot(contains('mushroom')),
          );
          expect(
            (secondJson['instructions'] as List).join(' ').toLowerCase(),
            contains('ham'),
          );

          // Validate full conversation history follows correct pattern
        },
        requiredCaps: {ProviderTestCaps.typedOutputWithTools},
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });
  });
}
