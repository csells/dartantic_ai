// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';
import 'package:http/http.dart' as http;

void main(List<String> args) async {
  stdout.writeln('=== OpenAI Responses Server-Side Tools Demos ===\n');

  await demoWebSearch();
  await demoImageGeneration();
  // await demoFileSearch();
  // await demoCodeInterpreter();
  // await demoComputerUse();
}

Future<void> demoWebSearch() async {
  stdout.writeln('📡 Web Search Demo\n');
  stdout.writeln('This demo searches for current information from the web.\n');

  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.webSearch},
    ),
  );

  const prompt = 'What are the top 3 more recent news headlines about Dart?';

  stdout.writeln('User: $prompt\n');
  stdout.writeln('${agent.displayName}:\n');

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Collect messages for history
    history.addAll(chunk.messages);

    // Show web search metadata
    final web = chunk.metadata['web_search'];
    if (web != null) {
      stdout.writeln('\n[web_search/${web['stage']}]');
      if (web['data'] != null) {
        dumpMetadata({'data': web['data']}, prefix: '  ', maxLength: 200);
      }
    }
  }

  dumpMessages(history);
}

Future<void> demoImageGeneration() async {
  stdout.writeln('🎨 Image Generation Demo\n');
  stdout.writeln('This demo generates images from text descriptions.\n');

  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.imageGeneration},
      imageGenerationConfig: ImageGenerationConfig(
        // Request progressive previews during generation (0-3)
        // 0 = no previews, just final; 1-3 = show intermediate renders
        partialImages: 3,
      ),
    ),
  );

  const prompt =
      'Generate a simple, minimalist logo for a fictional '
      'AI startup called "NeuralFlow". Use geometric shapes and '
      'a modern color palette with blue and purple gradients.';

  stdout.writeln('User: $prompt\n');
  stdout.writeln('${agent.displayName}:\n');

  var partialImageCount = 0;

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Collect messages for history
    history.addAll(chunk.messages);

    // Progressive images arrive via metadata during streaming
    final ig = chunk.metadata['image_generation'];
    if (ig != null) {
      final stage = ig['stage'];
      stdout.writeln('\n[image_generation/$stage]');

      // Progressive/partial images show intermediate render stages
      if (ig['partial_image_b64'] != null) {
        final b64 = ig['partial_image_b64'] as String;
        final index = ig['partial_image_index'] as int;

        // Decode and save the progressive image
        final bytes = base64.decode(b64);
        final filename =
            'tmp/partial_image_$index'
            '_${DateTime.now().millisecondsSinceEpoch}.png';
        final out = File(filename);
        out.createSync(recursive: true);
        out.writeAsBytesSync(bytes);

        stdout.writeln(
          '  🎨 Partial image #$index saved: $filename (${bytes.length} bytes)',
        );
        partialImageCount++;
      }
    }
  }

  if (partialImageCount > 0) {
    stdout.writeln('\nShowed $partialImageCount progressive render(s)');
  }

  // Final image arrives as a DataPart in the final message
  final imagePart = history.last.parts.whereType<DataPart>().single;
  assert(imagePart.mimeType.startsWith('image/'));
  final filename =
      'tmp/final_image'
      '_${DateTime.now().millisecondsSinceEpoch}.png';
  final out = File(filename);
  out.createSync(recursive: true);
  out.writeAsBytesSync(imagePart.bytes);

  stdout.writeln(
    '\n💾 Final image saved: $filename (${imagePart.bytes.length} bytes)',
  );

  dumpMessages(history);
}

/// Note: This requires files to be uploaded to OpenAI first
Future<void> demoFileSearch() async {
  stdout.writeln('🔍 File Search Demo\n');
  stdout.writeln('This demo searches through uploaded files.\n');
  stdout.writeln('Note: This requires files to be pre-uploaded to OpenAI.\n');

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.fileSearch},
      fileSearchConfig: FileSearchConfig(maxResults: 5),
    ),
  );

  const prompt =
      'Search for information about error handling best practices '
      'in the uploaded documentation files.';

  stdout.writeln('Prompt: $prompt\n');
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
                  '${truncateValue(first['content'], maxLength: 100)}',
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

/// Note: This tool allows the model to control a browser/desktop
Future<void> demoComputerUse() async {
  stdout.writeln('🖥️ Computer Use Demo\n');
  stdout.writeln(
    'Note: Computer use requires special setup and permissions.\n',
  );
  stdout.writeln(
    'This feature requires enterprise access and '
    'additional configuration.\n',
  );
  stdout.writeln('See docs/server-side-tools/computer-use.mdx for details.\n');

  // Computer use is typically not available without special permissions
  stdout.writeln(
    'This demo demonstrates browser/desktop control capabilities.\n',
  );

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.computerUse},
    ),
  );

  const prompt =
      'Navigate to a website and take a screenshot of the homepage. '
      'Describe what you see on the page.';

  stdout.writeln('Prompt: $prompt\n');
  stdout.writeln('Response:\n');

  await for (final chunk in agent.sendStream(prompt)) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Show computer use metadata
    final cu = chunk.metadata['computer_use'];
    if (cu != null) {
      stdout.writeln('\n[computer_use/${cu['stage']}]');
      if (cu['data'] != null) {
        final data = cu['data'];
        if (data is Map) {
          // Show action being performed
          if (data['action'] != null) {
            stdout.writeln('  Action: ${data['action']}');
          }
          // Show target element or coordinates
          if (data['target'] != null) {
            stdout.writeln(
              '  Target: ${truncateValue(data['target'], maxLength: 100)}',
            );
          }
          // Show result or screenshot info
          if (data['screenshot'] != null) {
            stdout.writeln('  Screenshot captured');
          }
        }
      }
    }
  }
  stdout.writeln('\n');
  stdout.writeln('Note: Computer use requires special permissions and setup.');
  stdout.writeln('It may not be available in all environments.');
}

void dumpMetadata(
  Map<String, Object?> metadata, {
  String prefix = '',
  int maxLength = 200,
}) {
  if (metadata.isEmpty) return;
  const encoder = JsonEncoder.withIndent('  ');
  final serialized = encoder.convert(metadata);
  final clipped = _clip(serialized, maxLength: maxLength);
  for (final line in clipped.split('\n')) {
    stdout.writeln('$prefix$line');
  }
}

String truncateValue(Object? value, {int maxLength = 200}) =>
    _clip(value?.toString() ?? 'null', maxLength: maxLength);

String _clip(String input, {int maxLength = 200}) {
  if (input.length <= maxLength) return input;
  final safeLength = maxLength <= 3 ? maxLength : maxLength - 3;
  final prefix = safeLength <= 0 ? '' : input.substring(0, safeLength);
  return '$prefix...';
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

Future<void> demoCodeInterpreter() async {
  stdout.writeln('🐍 Code Interpreter Demo with Container Reuse\n');

  // First session: Calculate Fibonacci numbers and store in container
  stdout.writeln('=== Session 1: Calculate Fibonacci Numbers ===\n');

  final agent1 = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.codeInterpreter},
    ),
  );

  const prompt1 =
      'Calculate the first 10 Fibonacci numbers and store them in a variable '
      'called "fib_sequence".';

  stdout.writeln('Prompt: $prompt1\n');
  stdout.writeln('Response:\n');

  String? capturedContainerId;
  final messages = <ChatMessage>[];

  await for (final chunk in agent1.sendStream(prompt1)) {
    // Collect messages for history
    messages.addAll(chunk.messages);

    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Capture and show code interpreter metadata
    final ci = chunk.metadata['code_interpreter'] as Map<String, dynamic>?;
    final stage = ci?['stage'] as String?;
    if (stage != null && stage != 'code_delta') {
      // stdout.writeln('\n[code_interpreter/$stage]');

      // Capture container ID for reuse
      final data = ci?['data'] as Map<String, dynamic>;
      capturedContainerId = data['container_id'] as String?;
    }
  }

  stdout.writeln('\n\n');

  // Check if we captured a container ID
  if (capturedContainerId == null) {
    stdout.writeln('  ❌ Failed to capture container ID from first session');
    return;
  }

  // Second session: Explicitly configure container reuse
  stdout.writeln(
    '🔄 Configuring agent to reuse container: $capturedContainerId\n',
  );

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

  stdout.writeln('Prompt: $prompt2\n');
  stdout.writeln('Response:\n');

  final downloadedFiles = <String>{}; // Track already downloaded files

  await for (final chunk in agent2.sendStream(
    prompt2,
    history: messages, // Pass conversation history here
  )) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Check for images in message parts
    // for (final msg in chunk.messages) {
    //   if (msg.role != ChatMessageRole.model) continue;
    //   for (final part in msg.parts) {
    //     if (part is LinkPart) {
    //       stdout.writeln('\n📎 Image URL: ${part.url}');
    //     } else if (part is DataPart && part.mimeType.startsWith('image/')) {
    //       stdout.writeln(
    //         '\n📎 Image data: ${part.mimeType}, ${part.bytes.length} bytes',
    //       );
    //     }
    //   }
    // }

    // Show code interpreter metadata for second session
    final ci = chunk.metadata['code_interpreter'];
    if (ci != null) {
      final stage = ci['stage'] as String?;
      if (stage != null && stage != 'code_delta') {
        stdout.writeln('\n[code_interpreter/$stage]');

        final data = ci['data'];
        if (data is Map) {
          // Verify we're using the same container
          if (data['container_id'] != null) {
            final currentContainerId = data['container_id'] as String;
            if (currentContainerId == capturedContainerId) {
              stdout.writeln('  ✅ Reusing container: $currentContainerId');
            } else {
              stdout.writeln('  ⚠️ New container: $currentContainerId');
            }
          }

          // Show code
          if (data['code'] != null) stdout.writeln('  Code: ${data['code']}');

          // Show generated files and download them
          if (data['files'] != null && data['files'] is List) {
            final files = data['files'] as List;
            stdout.writeln('  📊 Generated ${files.length} file(s)');
            for (final file in files) {
              if (file is Map) {
                final fileId = file['file_id'] as String?;
                final filename = file['filename'] as String? ?? 'unnamed_file';
                final containerId =
                    file['container_id'] as String? ??
                    data['container_id'] as String?;
                if (fileId != null && containerId != null) {
                  // Only download if we haven't already downloaded this file
                  if (!downloadedFiles.contains(fileId)) {
                    downloadedFiles.add(fileId);
                    await downloadContainerFile(containerId, fileId, filename);
                  }
                }
              } else if (file is String) {
                // File might just be a string ID
                final containerId = data['container_id'] as String?;
                if (containerId != null) {
                  // Only download if we haven't already downloaded this file
                  if (!downloadedFiles.contains(file)) {
                    downloadedFiles.add(file);
                    await downloadContainerFile(containerId, file, '$file.png');
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
