// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
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

  stdout.writeln('Prompt: $prompt1');
  stdout.writeln('Response:');

  String? capturedContainerId;
  final messages = <ChatMessage>[];

  await for (final chunk in agent1.sendStream(prompt1)) {
    // Collect messages for history
    messages.addAll(chunk.messages);

    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);
  }

  stdout.writeln();

  // Extract container_id from message metadata (synthetic summary events)
  for (final msg in messages) {
    final ciEvents = msg.metadata['code_interpreter'] as List?;
    if (ciEvents != null) {
      for (final event in ciEvents) {
        if (event['container_id'] != null) {
          capturedContainerId = event['container_id'] as String?;
          break;
        }
      }
    }
    if (capturedContainerId != null) break;
  }

  if (capturedContainerId == null) {
    stdout.writeln('❌ Failed to capture container ID from first session');
    return;
  }

  stdout.writeln('✅ Captured container ID: $capturedContainerId');
  stdout.writeln();

  // Second session: Explicitly configure container reuse
  stdout.writeln('=== Session 2: Calculate Golden Ratio ===');

  final agent2 = Agent(
    'openai-responses',
    chatModelOptions: OpenAIResponsesChatModelOptions(
      serverSideTools: const {OpenAIServerSideTool.codeInterpreter},
      codeInterpreterConfig: CodeInterpreterConfig(
        containerId: capturedContainerId, // Explicitly request container reuse
      ),
    ),
  );

  const prompt2 =
      'Using the fib_sequence variable we created earlier, calculate the '
      'golden ratio (skipping the first term, since it is 0). '
      'Create a plot showing how the ratio converges to the golden ratio.';

  stdout.writeln('Prompt: $prompt2');
  stdout.writeln('Response:');

  final downloadedFiles = <String>{}; // Track already downloaded files

  final session2Messages = <ChatMessage>[];

  await for (final chunk in agent2.sendStream(
    prompt2,
    history: messages, // Pass conversation history here
  )) {
    session2Messages.addAll(chunk.messages);

    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);
  }

  stdout.writeln();

  // Verify container reuse by checking session 2 message metadata
  for (final msg in session2Messages) {
    final ciEvents = msg.metadata['code_interpreter'] as List?;
    if (ciEvents != null) {
      for (final event in ciEvents) {
        if (event['container_id'] != null) {
          final currentContainerId = event['container_id'] as String;
          if (currentContainerId == capturedContainerId) {
            stdout.writeln('✅ Container reused: $currentContainerId');
          } else {
            stdout.writeln(
              '⚠️  New container: $currentContainerId '
              '(expected: $capturedContainerId)',
            );
          }

          // Download generated files
          if (event['results'] != null && event['results'] is List) {
            final results = event['results'] as List;
            for (final result in results) {
              if (result is Map && result['type'] == 'file') {
                final fileId = result['file_id'] as String?;
                final filename =
                    result['filename'] as String? ?? 'unnamed_file';

                if (fileId != null && !downloadedFiles.contains(fileId)) {
                  downloadedFiles.add(fileId);
                  stdout.writeln('📊 Downloading: $filename');
                  await downloadContainerFile(
                    currentContainerId,
                    fileId,
                    filename,
                  );
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Container files use a different endpoint than regular files
Future<void> downloadContainerFile(
  String containerId,
  String fileId,
  String filename,
) async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null) {
    stdout.writeln('     ❌ OPENAI_API_KEY not set');
    return;
  }

  try {
    // Container files use this endpoint pattern
    final url = Uri.parse(
      'https://api.openai.com/v1/containers/$containerId/files/$fileId/content',
    );

    stdout.writeln('     📄 $filename (ID: $fileId)');
    stdout.writeln('     📥 Downloading from container...');

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

      // Get the absolute path for the file
      final absolutePath = file.absolute.path;

      stdout.writeln('     ✅ Downloaded to: $absolutePath');
      stdout.writeln('        Size: ${result.bodyBytes.length} bytes');
    } else {
      stdout.writeln('     ❌ Failed to download: HTTP ${result.statusCode}');
    }

    client.close();
  } on Exception catch (e) {
    stdout.writeln('     ❌ Download error: $e');
  }
}
