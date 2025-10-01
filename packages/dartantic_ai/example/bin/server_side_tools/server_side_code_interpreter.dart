// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';
import 'package:http/http.dart' as http;

void main(List<String> args) async {
  stdout.writeln('🐍 Code Interpreter Demo with Container Reuse');

  // First session: Calculate Fibonacci numbers and store in container
  stdout.writeln('=== Session 1: Calculate Fibonacci Numbers ===');

  final agent1 = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.codeInterpreter},
    ),
  );

  const prompt1 =
      'Calculate the first 10 Fibonacci numbers and store them in a variable '
      'called "fib_sequence".';

  stdout.writeln('User: $prompt1');
  stdout.writeln('${agent1.displayName}: ');

  final history = <ChatMessage>[];
  await for (final chunk in agent1.sendStream(prompt1)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  // Extract container_id from message metadata
  final containerId = containerIdFrom(history)!;
  final session1MessageCount = history.length;

  stdout.writeln('✅ Captured container ID: $containerId');
  stdout.writeln();

  // Second session: Explicitly configure container reuse
  stdout.writeln('=== Session 2: Calculate Golden Ratio ===');

  final agent2 = Agent(
    'openai-responses',
    chatModelOptions: OpenAIResponsesChatModelOptions(
      serverSideTools: const {OpenAIServerSideTool.codeInterpreter},
      codeInterpreterConfig: CodeInterpreterConfig(
        containerId: containerId, // Explicitly request container reuse
      ),
    ),
  );

  const prompt2 =
      'Using the fib_sequence variable we created earlier, calculate the '
      'golden ratio (skipping the first term, since it is 0). '
      'Create a plot showing how the ratio converges to the golden ratio.';

  stdout.writeln('User: $prompt2');
  stdout.write('${agent2.displayName}: ');

  await for (final chunk in agent2.sendStream(
    prompt2,
    history: history, // Pass conversation history here
  )) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  // Verify container reuse by checking session 2 message metadata
  final sessions2ContainerId = containerIdFrom(
    history.skip(session1MessageCount),
  );

  if (sessions2ContainerId != containerId) {
    stdout.writeln(
      '❌ Container NOT reused: $containerId != $sessions2ContainerId',
    );
    return;
  } else {
    stdout.writeln('✅ Container reused: $containerId');
  }

  for (final msg in history.skip(session1MessageCount)) {
    final ciEvents = msg.metadata['code_interpreter'] as List?;
    if (ciEvents != null) {
      for (final event in ciEvents) {
        if (event['container_id'] != null) {
          // Download generated files
          if (event['results'] != null && event['results'] is List) {
            final results = event['results'] as List;
            for (final result in results) {
              if (result is Map && result['type'] == 'file') {
                final fileId = result['file_id'] as String?;
                final filename =
                    result['filename'] as String? ?? 'unnamed_file';

                if (fileId != null) {
                  stdout.writeln();
                  await downloadContainerFile(containerId, fileId, filename);
                }
              }
            }
          }
          break; // Found container_id, done checking
        }
      }
    }
  }

  stdout.writeln();
  dumpMessages(history);
}

String? containerIdFrom(Iterable<ChatMessage> messages) {
  for (final msg in messages) {
    final ciEvents = msg.metadata['code_interpreter'] as List?;
    if (ciEvents != null) {
      for (final event in ciEvents) {
        if (event['container_id'] != null) return event['container_id'];
      }
    }
  }

  return null;
}

/// Container files use a different endpoint than regular files
/// TODO: use native openai_core API for this
Future<void> downloadContainerFile(
  String containerId,
  String fileId,
  String filename,
) async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null) {
    stdout.writeln('❌ OPENAI_API_KEY not set');
    return;
  }

  // Container files use this endpoint pattern
  final url = Uri.parse(
    'https://api.openai.com/v1/containers/$containerId/files/$fileId/content',
  );

  stdout.writeln('📊 Downloading: $filename');
  stdout.writeln('   File ID: $fileId');
  stdout.writeln('   Container: $containerId');

  final client = http.Client();
  final result = await client.get(
    url,
    headers: {'Authorization': 'Bearer $apiKey'},
  );

  if (result.statusCode == 200) {
    final outputPath = 'tmp/$filename';
    final file = File(outputPath);
    await file.create(recursive: true);
    await file.writeAsBytes(result.bodyBytes);

    final absolutePath = file.absolute.path;

    stdout.writeln('   ✅ Downloaded to: $absolutePath');
    stdout.writeln('   Size: ${result.bodyBytes.length} bytes');
  } else {
    stdout.writeln('   ❌ Failed: HTTP ${result.statusCode}');
    stdout.writeln('   Response: ${result.body}');
  }

  client.close();
}
