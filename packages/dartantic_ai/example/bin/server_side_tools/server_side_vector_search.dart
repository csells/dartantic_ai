// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('🔍 Vector Search Demo');
  stdout.writeln('This demo searches through uploaded files.');
  stdout.writeln('Note: This requires files to be pre-uploaded to OpenAI.');

  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.fileSearch},
      fileSearchConfig: FileSearchConfig(maxResults: 5),
    ),
  );

  const prompt =
      'Search for information about error handling best practices '
      'in the uploaded documentation files.';

  stdout.writeln('Prompt: $prompt');
  stdout.writeln('Response:\n');

  await for (final chunk in agent.sendStream(prompt)) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Show file search metadata
    final fs = chunk.metadata['file_search'];
    if (fs != null) {
      stdout.writeln('\n[file_search/${fs['stage']}]');
      if (fs['data'] != null) {
        final data = fs['data'];
        if (data is Map) {
          // Show search query
          if (data['query'] != null) {
            stdout.writeln('  Query: ${data['query']}');
          }
          // Show number of results
          if (data['results'] != null && data['results'] is List) {
            final results = data['results'] as List;
            stdout.writeln('  Found: ${results.length} results');
            // Show first result preview
            if (results.isNotEmpty) {
              final first = results[0];
              if (first is Map && first['content'] != null) {
                stdout.writeln(
                  '  Preview: '
                  '${clipWithNull(first['content'])}',
                );
              }
            }
          }
        }
      }
    }
  }
  stdout.writeln('\n');
  stdout.writeln(
    'Note: If no results were found, you may need to upload files first',
  );
  stdout.writeln('using the OpenAI Files API before running this demo.');
}
