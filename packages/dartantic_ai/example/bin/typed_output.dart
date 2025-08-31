// ignore_for_file: avoid_print, unreachable_from_main, unused_local_variable

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';
import 'package:json_schema/json_schema.dart';

void main() async {
  final provider = Providers.openai;
  assert(provider.caps.contains(ProviderCaps.typedOutputWithTools));
  final agent = Agent.forProvider(
    provider,
    tools: [currentDateTimeTool, temperatureTool, recipeLookupTool],
  );

  await jsonOutput(agent);
  await jsonOutputStreaming(agent);
  await mapOutput(agent);
  await typedOutput(agent);
  await typedOutputWithCodeGen(agent);
  await typedOutputWithToolCalls(agent);
  await typedOutputWithToolCallsAndMultipleTurns(provider);
  await typedOutputWithToolCallsAndMultipleTurnsStreaming(provider);

  exit(0);
}

Future<void> jsonOutput(Agent agent) async {
  print('═══ ${agent.displayName} JSON Output ═══');

  final result = await agent.send(
    'What is the Windy City in the US of A?',
    outputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'town': {'type': 'string'},
        'country': {'type': 'string'},
      },
      'required': ['town', 'country'],
    }),
  );

  final map = jsonDecode(result.output) as Map<String, dynamic>;
  print('town: ${map['town']}');
  print('country: ${map['country']}');
  dumpMessages(result.messages);
  print('--------------------------------');
  print('');
}

Future<void> jsonOutputStreaming(Agent agent) async {
  print('═══ ${agent.displayName} JSON Output Stream ═══');

  final text = StringBuffer();
  final history = <ChatMessage>[];
  await agent
      .sendStream(
        'What is the Windy City in the US of A?',
        outputSchema: JsonSchema.create({
          'type': 'object',
          'properties': {
            'town': {'type': 'string'},
            'country': {'type': 'string'},
          },
          'required': ['town', 'country'],
        }),
      )
      .forEach((r) {
        text.write(r.output);
        history.addAll(r.messages);
        stdout.write(r.output);
      });
  stdout.writeln();

  final map = jsonDecode(text.toString()) as Map<String, dynamic>;
  print('town: ${map['town']}');
  print('country: ${map['country']}');
  dumpMessages(history);
  print('--------------------------------');
  print('');
}

Future<void> mapOutput(Agent agent) async {
  print('═══ ${agent.displayName} Map Output ═══');

  final result = await agent.sendFor<Map<String, dynamic>>(
    'What is the Windy City in the US of A?',
    outputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'town': {'type': 'string'},
        'country': {'type': 'string'},
      },
      'required': ['town', 'country'],
    }),
  );

  print('town: ${result.output['town']}');
  print('country: ${result.output['country']}');
  dumpMessages(result.messages);
  print('--------------------------------');
  print('');
}

Future<void> typedOutput(Agent agent) async {
  print('═══ ${agent.displayName} Typed Output ═══');

  final result = await agent.sendFor<TownAndCountry>(
    'What is the Windy City in the US of A?',
    outputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'town': {'type': 'string'},
        'country': {'type': 'string'},
      },
      'required': ['town', 'country'],
    }),
    outputFromJson: (json) =>
        TownAndCountry(town: json['town'], country: json['country']),
  );

  print('town: ${result.output.town}');
  print('country: ${result.output.country}');
  dumpMessages(result.messages);
  print('--------------------------------');
  print('');
}

Future<void> typedOutputWithCodeGen(Agent agent) async {
  print(
    '═══ '
    '${agent.displayName} Typed Output with Code Gen (fromJson + schema) '
    '═══',
  );

  final result = await agent.sendFor<TownAndCountry>(
    'What is the Windy City in the US of A?',
    outputSchema: JsonSchema.create(TownAndCountry.schemaMap),
    outputFromJson: TownAndCountry.fromJson,
  );

  print('town: ${result.output.town}');
  print('country: ${result.output.country}');
  dumpMessages(result.messages);
  print('--------------------------------');
  print('');
}

Future<void> typedOutputWithToolCalls(Agent agent) async {
  print('═══ ${agent.displayName} Typed Output with Tool Calls ═══');

  final result = await agent.sendFor<TimeAndTemperature>(
    'What is the time and temperature in Portland, OR?',
    outputSchema: TimeAndTemperature.schema,
    outputFromJson: TimeAndTemperature.fromJson,
  );

  print('time: ${result.output.time}');
  print('temperature: ${result.output.temperature}');
  dumpMessages(result.messages);
  print('--------------------------------');
  print('');
}

Future<void> typedOutputWithToolCallsAndMultipleTurns(Provider provider) async {
  final agent = Agent.forProvider(provider, tools: [recipeLookupTool]);

  print(
    '═══ '
    '${agent.displayName} Typed Output with Tool Calls and Multiple Turns '
    '═══',
  );

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

  // First turn: Look up the recipe
  final history = <ChatMessage>[ChatMessage.system('You are an expert chef.')];
  final result = await agent.sendFor<Map<String, dynamic>>(
    "Can you show me grandma's mushroom omelette recipe?",
    outputSchema: recipeSchema,
    history: history,
  );
  history.addAll(result.messages);
  dumpMessages(history);

  final json = result.output;
  dumpRecipe(json);

  // Second turn: Modify the recipe
  final secondResult = await agent.sendFor<Map<String, dynamic>>(
    'Can you update it to replace the mushrooms with ham?',
    history: history,
    outputSchema: recipeSchema,
  );
  history.addAll(secondResult.messages);
  dumpRecipe(secondResult.output);
  dumpMessages(history);
}

Future<void> typedOutputWithToolCallsAndMultipleTurnsStreaming(
  Provider provider,
) async {
  final agent = Agent.forProvider(provider, tools: [recipeLookupTool]);

  print(
    '═══ '
    '${agent.displayName} Typed Output with Tool Calls and Multiple Turns '
    'Stream '
    '═══',
  );

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

  // First turn: Look up the recipe (streaming with runStream)
  final history = <ChatMessage>[ChatMessage.system('You are an expert chef.')];
  print('First turn - streaming JSON for recipe lookup:');
  final firstJsonChunks = <String>[];
  await for (final result in agent.sendStream(
    "Can you show me grandma's mushroom omelette recipe?",
    outputSchema: recipeSchema,
    history: history,
  )) {
    if (result.output.isNotEmpty) {
      firstJsonChunks.add(result.output);
      stdout.write(result.output);
    }
    history.addAll(result.messages);
  }
  stdout.writeln();

  // Parse first result
  final firstCompleteJson = firstJsonChunks.join();
  final firstResult = jsonDecode(firstCompleteJson) as Map<String, dynamic>;

  print('First recipe:');
  dumpRecipe(firstResult);

  // Second turn: Modify the recipe (streaming with runStream)
  print('Second turn - streaming JSON for recipe modification:');
  final secondJsonChunks = <String>[];
  await for (final result in agent.sendStream(
    'Can you update it to replace the mushrooms with ham?',
    history: history,
    outputSchema: recipeSchema,
  )) {
    if (result.output.isNotEmpty) {
      secondJsonChunks.add(result.output);
      stdout.write(result.output);
    }
    history.addAll(result.messages);
  }
  stdout.writeln();

  // Parse second result
  final secondCompleteJson = secondJsonChunks.join();
  final secondResult = jsonDecode(secondCompleteJson) as Map<String, dynamic>;

  print('Modified recipe:');
  dumpRecipe(secondResult);
  print('--------------------------------');
  print('');
}

void dumpRecipe(Map<String, dynamic> json) {
  print('--------------------------------');
  print('name: ${json['name']}');
  print('ingredients: ${json['ingredients']}');
  print('instructions: ${json['instructions']}');
  print('prep_time: ${json['prep_time']}');
  print('cook_time: ${json['cook_time']}');
  print('servings: ${json['servings']}');
  print('--------------------------------');
}
