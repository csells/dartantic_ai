// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main() async {
  print('=== Agent Example ===\n');
  print('This example demonstrates an AI agent that can use multiple tools');
  print('to help answer questions and perform tasks.\n');

  // Create an agent with multiple tools
  final claudeAgent = Agent('anthropic', tools: exampleTools);

  // Weather and temperature conversion
  print('--- ${claudeAgent.model} Weather Query ---');
  print(
    "User: What's the weather in Boston? "
    "If it's in Celsius, convert to Fahrenheit.",
  );

  final response1 = await claudeAgent.send(
    "What's the weather in Boston? If it's in Celsius, convert to Fahrenheit.",
  );

  print('Agent: ${response1.output}\n');

  // Travel planning
  print('--- ${claudeAgent.model} Travel Planning ---');
  print(
    "User: I'm planning a trip from New York to San Francisco. "
    'Can you tell me the distance and check the weather in both cities?',
  );

  final response2 = await claudeAgent.send(
    "I'm planning a trip from New York to San Francisco. "
    'Can you tell me the distance and check the weather in both cities?',
  );

  print('Agent: ${response2.output}\n');

  // Multi-step task with streaming
  print('--- ${claudeAgent.model} Investment Research (Streaming) ---');
  print(
    'User: Check the stock prices for AAPL and MSFT, then tell me which one '
    'is performing better today.',
  );
  print('Agent: ');

  await for (final chunk in claudeAgent.sendStream(
    'Check the stock prices for AAPL and MSFT, then tell me which one '
    'is performing better today.',
  )) {
    stdout.write(chunk.output);
  }
  print('\n');

  // Agent with different providers
  print('--- Cross-Provider Comparison ---');

  // OpenAI agent
  final openaiAgent = Agent(
    'openai-responses',
    tools: [currentDateTimeTool, weatherTool],
  );

  stdout.write('\n${openaiAgent.model}: ');
  await openaiAgent
      .sendStream("What time is it and how's the weather in London?")
      .forEach((result) => stdout.write(result.output));
  stdout.writeln();

  // Google agent
  final googleAgent = Agent(
    'google',
    tools: [currentDateTimeTool, weatherTool],
  );

  stdout.write('\n${googleAgent.model}: ');
  await googleAgent
      .sendStream("What time is it and how's the weather in London?")
      .forEach((result) => stdout.write(result.output));
  stdout.writeln();

  exit(0);
}
