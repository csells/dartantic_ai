// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('🌐 Anthropic Server-Side Web Fetch\n');
  stdout.writeln(
    "This demo fetches remote content using Claude's server-side "
    'web fetch tool.\n',
  );

  final agent = Agent(
    'anthropic:claude-sonnet-4-5-20250929',
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
    dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  _saveFetchedDocuments(history);
  dumpMessages(history);

  stdout.writeln('✅ Completed web fetch demo.');
}

void _saveFetchedDocuments(List<ChatMessage> history) {
  var savedAny = false;
  for (final message in history) {
    for (final part in message.parts) {
      if (part is DataPart) {
        final filename = part.name ?? 'fetched_document';
        final file = File('tmp/$filename');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(part.bytes);
        stdout.writeln(
          '💾 Saved fetched document: tmp/$filename (${part.mimeType})',
        );
        savedAny = true;
      }
    }
  }

  if (!savedAny) {
    stdout.writeln('⚠️  No downloadable documents were returned.');
  }
}
