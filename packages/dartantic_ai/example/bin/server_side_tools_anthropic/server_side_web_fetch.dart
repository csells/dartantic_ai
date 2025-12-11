// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('Anthropic Server-Side Web Fetch\n');

  final agent = Agent(
    'anthropic',
    chatModelOptions: const AnthropicChatOptions(
      serverSideTools: {AnthropicServerSideTool.webFetch},
    ),
  );

  const prompt =
      'Retrieve https://sellsbrothers.com. Summarize in one sentence.';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    // dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  // web_fetch returns fetched document bytes; this saves them to disk.
  dumpAssetsFromHistory(history, 'tmp', fallbackPrefix: 'fetched_document');
  exit(0);
}
