import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'claude';
  await multipleTools(model);
  await multipleToolsStream(model);
  await multipleDependentTools(model);
  await multipleDependentToolsStream(model);
  exit(0);
}

Future<void> multipleTools(String model) async {
  stdout.writeln('\n## Multiple Tools');

  final agent = Agent(
    model,
    tools: [currentDateTimeTool, weatherTool, stockPriceTool],
    enableThinking: true,
  );

  const prompt =
      'Tell me the current time, the weather in NYC, '
      'and the price of GOOGL stock.';

  stdout.writeln('User: $prompt');
  final result = await agent.send(prompt);
  stdout.writeln('${agent.displayName}: ${result.output}\n');
  dumpMessages(result.messages);
}

Future<void> multipleToolsStream(String model) async {
  stdout.writeln('\n## Multiple Tools Streaming');

  final agent = Agent(
    model,
    tools: [currentDateTimeTool, weatherTool, stockPriceTool],
    enableThinking: true,
  );

  const prompt =
      'Tell me the current time, the weather in NYC, '
      'and the price of GOOGL stock.';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');
  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();
  dumpMessages(history);
}

Future<void> multipleDependentTools(String model) async {
  stdout.writeln('\n## Multiple Dependent Tools');

  final agent = Agent(
    model,
    tools: [weatherTool, temperatureConverterTool],
    enableThinking: true,
  );

  const prompt = 'What is the temperature in Miami in Fahrenheit?';
  stdout.writeln('User: $prompt');
  final result = await agent.send(prompt);
  stdout.writeln('${agent.displayName}: ${result.output}\n');
  dumpMessages(result.messages);
}

Future<void> multipleDependentToolsStream(String model) async {
  stdout.writeln('\n## Multiple Dependent Tools Streaming');

  final agent = Agent(
    model,
    tools: [weatherTool, temperatureConverterTool],
    enableThinking: true,
  );

  const prompt = 'What is the temperature in Miami in Fahrenheit?';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');
  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();
  dumpMessages(history);
}
