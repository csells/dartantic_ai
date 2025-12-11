// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

void main(List<String> args) async {
  stdout.writeln('Anthropic Server-Side Web Search\n');

  final agent = Agent(
    'anthropic',
    chatModelOptions: const AnthropicChatOptions(
      serverSideTools: {AnthropicServerSideTool.webSearch},
    ),
  );

  const prompt =
      'Search the web for the three most recent announcements '
      'about the Dart programming language and summarize them.';
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
