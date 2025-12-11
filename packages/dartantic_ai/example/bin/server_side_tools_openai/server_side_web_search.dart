// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

void main(List<String> args) async {
  stdout.writeln('Open AI Responses: Web Search Demo\n');

final agent = Agent(
  'openai-responses',
  chatModelOptions: const OpenAIResponsesChatModelOptions(
    serverSideTools: {OpenAIServerSideTool.webSearch},
  ),
);

  const prompt =
      'What are the top 3 more recent news headlines about '
      'Dart the programming language?';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    // dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  exit(0);
}
