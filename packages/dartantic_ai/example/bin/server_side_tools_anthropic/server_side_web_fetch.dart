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
      'Fetch the article at https://example.com and summarize the key '
      'information in a few bullet points. Include the original text as an '
      'attachment if possible.';

  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    // dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  dumpAssetsFromHistory(history, 'tmp', fallbackPrefix: 'fetched_document');
  dumpMessages(history);
  exit(0);
}
