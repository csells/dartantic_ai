import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'openai-responses';
  await singleToolCall(model);
  await singleToolCallStream(model);
  exit(0);
}

Future<void> singleToolCall(String model) async {
  stdout.writeln('\n## Single Tool Call');

  final agent = Agent(model, tools: [weatherTool]);
  const prompt = 'What is the weather in Boston?';
  stdout.writeln('User: $prompt');
  final response = await agent.send(prompt);
  stdout.writeln('${agent.displayName}: ${response.output}');
  dumpMessages(response.messages);
}

Future<void> singleToolCallStream(String model) async {
  stdout.writeln('\n## Single Tool Call Streaming');

  final agent = Agent(model, tools: [weatherTool]);
  const prompt = 'What is the weather in Boston?';
  final history = <ChatMessage>[];
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();
  dumpMessages(history);
}
