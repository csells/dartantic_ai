// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main() async {
  print('=== Multiple Tool Call Example ===\n');

  // Example with multiple independent tools
  print('--- Multiple Independent Tools (OpenAI) ---');
  var agent = Agent(
    'openai:gpt-4o-mini',
    tools: [currentDateTimeTool, weatherTool, stockPriceTool],
  );

  print(
    'User: Tell me the current time, the weather in NYC, '
    'and the price of GOOGL stock.',
  );
  var response = await agent.send(
    'Tell me the current time, the weather in NYC, '
    'and the price of GOOGL stock.',
  );
  print('Assistant: ${response.output}\n');
  dumpMessages(response.messages);

  // Example with dependent tool calls
  print('--- Dependent Tool Calls (Anthropic) ---');
  agent = Agent(
    'anthropic:claude-3-5-haiku-latest',
    tools: [weatherTool, temperatureConverterTool],
  );

  print(
    'User: What is the temperature in Miami? Then convert it to Fahrenheit.',
  );
  response = await agent.send(
    'What is the temperature in Miami? Then convert it to Fahrenheit.',
  );
  print('Assistant: ${response.output}\n');

  // Example with calculation tools
  print('--- Travel Planning Tools (Google) ---');
  agent = Agent(
    'google:gemini-2.0-flash',
    tools: [distanceCalculatorTool, weatherTool, currentDateTimeTool],
  );

  print('User: I want to travel from New York to Boston...');
  response = await agent.send(
    'I want to travel from New York to Boston. '
    'Tell me the distance, current weather in both cities, '
    'and what time it is now.',
  );
  print('Assistant: ${response.output}\n');

  // Streaming with multiple tools
  print('--- Streaming Multiple Tool Calls (Anthropic) ---');
  agent = Agent(
    'anthropic:claude-3-5-haiku-latest',
    tools: exampleTools, // All tools available
  );

  print(
    'User: Check the weather in Seattle and tell me the distance from Seattle '
    'to Portland.',
  );
  print('Assistant: ');
  await for (final chunk in agent.sendStream(
    'Check the weather in Seattle and tell me the distance from Seattle '
    'to Portland.',
  )) {
    stdout.write(chunk.output);
  }
  print('\n');

  // Streaming with multiple tools via OpenAI Responses API
  print('--- Streaming Multiple Tool Calls (OpenAI Responses) ---');
  agent = Agent(
    'openai-responses',
    tools: exampleTools, // All tools available
  );

  print(
    'User: Check the weather in Seattle and tell me the distance from Seattle '
    'to Portland.',
  );
  print('Assistant: ');
  await for (final chunk in agent.sendStream(
    'Check the weather in Seattle and tell me the distance from Seattle '
    'to Portland.',
  )) {
    stdout.write(chunk.output);
  }
  print('\n');

  exit(0);
}
