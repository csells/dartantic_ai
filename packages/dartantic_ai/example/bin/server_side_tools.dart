// ignore_for_file: avoid_print, avoid_dynamic_calls, unreachable_from_main

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

Future<void> main(List<String> args) async {
  print('=== OpenAI Responses Server-Side Tools Demos ===\n');

  // await demoWebSearch();
  // await demoImageGeneration();
  // await demoFileSearch();
  // await demoComputerUse();
  await demoCodeInterpreter();
}

/// Demonstrates web search capabilities
Future<void> demoWebSearch() async {
  print('📡 Web Search Demo\n');
  print('This demo searches for current information from the web.\n');

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatOptions(
      serverSideTools: {OpenAIServerSideTool.webSearch},
    ),
  );

  const prompt =
      'What are the top 3 news articles about Dart? Just the headlines';

  print('Prompt: $prompt\n');
  print('Response:\n');

  await for (final chunk in agent.sendStream(prompt)) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Show web search metadata
    final web = chunk.metadata['web_search'];
    if (web != null) {
      stdout.writeln('\n[web_search/${web['stage']}]');
      if (web['data'] != null) {
        dumpMetadata({'data': web['data']}, prefix: '  ', maxLength: 200);
      }
    }
  }
  print('\n');
}

/// Demonstrates image generation capabilities
Future<void> demoImageGeneration() async {
  print('🎨 Image Generation Demo\n');
  print('This demo generates images from text descriptions.\n');

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatOptions(
      serverSideTools: {OpenAIServerSideTool.imageGeneration},
    ),
  );

  const prompt =
      'Generate a simple, minimalist logo for a fictional '
      'AI startup called "NeuralFlow". Use geometric shapes and '
      'a modern color palette with blue and purple gradients.';

  print('Prompt: $prompt\n');
  print('Response:\n');

  var imageCount = 0;

  await for (final chunk in agent.sendStream(prompt)) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Show image generation metadata
    final ig = chunk.metadata['image_generation'];
    if (ig != null) {
      final stage = ig['stage'];
      if (stage != 'partial_image') {
        // Don't show partial_image as it's too verbose
        stdout.writeln('\n[image_generation/$stage]');
      }
    }

    // Handle generated images
    for (final m in chunk.messages) {
      if (m.role != ChatMessageRole.model) continue;
      for (final p in m.parts) {
        if (p is LinkPart) {
          stdout.writeln('\n📎 Image URL: ${p.url}');
        } else if (p is DataPart && p.mimeType.startsWith('image/')) {
          imageCount++;
          final filename =
              'tmp/generated_image_$imageCount'
              '_${DateTime.now().millisecondsSinceEpoch}.png';
          final out = File(filename);
          out.createSync(recursive: true);
          out.writeAsBytesSync(p.bytes);

          stdout.writeln('\n💾 Image saved to: $filename');
          stdout.writeln('   Size: ${p.bytes.length} bytes');
          stdout.writeln('   Type: ${p.mimeType}');

          // Show first 100 chars of base64 for verification
          final b64Preview = base64.encode(p.bytes).substring(0, 100);
          stdout.writeln('   Data (preview): $b64Preview...');
        }
      }
    }
  }
  print('\n');
}

/// Demonstrates file search capabilities
/// Note: This requires files to be uploaded to OpenAI first
Future<void> demoFileSearch() async {
  print('🔍 File Search Demo\n');
  print('This demo searches through uploaded files.\n');
  print('Note: This requires files to be pre-uploaded to OpenAI.\n');

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatOptions(
      serverSideTools: {OpenAIServerSideTool.fileSearch},
      fileSearchConfig: FileSearchConfig(maxResults: 5),
    ),
  );

  const prompt =
      'Search for information about error handling best practices '
      'in the uploaded documentation files.';

  print('Prompt: $prompt\n');
  print('Response:\n');

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
  print('\n');
  print('Note: If no results were found, you may need to upload files first');
  print('using the OpenAI Files API before running this demo.');
}

/// Demonstrates computer use capabilities
/// Note: This tool allows the model to control a browser/desktop
Future<void> demoComputerUse() async {
  print('🖥️ Computer Use Demo\n');
  print('Note: Computer use requires special setup and permissions.\n');
  print(
    'This feature requires enterprise access and '
    'additional configuration.\n',
  );
  print('See docs/server-side-tools/computer-use.mdx for details.\n');

  // Computer use is typically not available without special permissions
  print('This demo demonstrates browser/desktop control capabilities.\n');

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatOptions(
      serverSideTools: {OpenAIServerSideTool.computerUse},
    ),
  );

  const prompt =
      'Navigate to a website and take a screenshot of the homepage. '
      'Describe what you see on the page.';

  print('Prompt: $prompt\n');
  print('Response:\n');

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
  print('\n');
  print('Note: Computer use requires special permissions and setup.');
  print('It may not be available in all environments.');
}

/// Demonstrates code interpreter capabilities
Future<void> demoCodeInterpreter() async {
  print('🐍 Code Interpreter Demo\n');
  print('This demo executes Python code to solve mathematical problems.\n');

  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatOptions(
      serverSideTools: {OpenAIServerSideTool.codeInterpreter},
    ),
  );

  const prompt =
      'Calculate the first 10 Fibonacci numbers and plot them in a graph. '
      'Also find the golden ratio from the sequence.';

  print('Prompt: $prompt\n');
  print('Response:\n');

  await for (final chunk in agent.sendStream(prompt)) {
    // Stream the text response
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Show code interpreter metadata
    final ci = chunk.metadata['code_interpreter'];
    if (ci != null) {
      final stage = ci['stage'] as String?;
      if (stage != null) {
        stdout.writeln('\n[code_interpreter/$stage]');

        final data = ci['data'];
        if (data is Map) {
          // Show code being executed
          if (data['code'] != null) {
            stdout.writeln('  Code:');
            final codeLines = data['code'].toString().split('\n');
            for (final line in codeLines.take(5)) {
              stdout.writeln('    $line');
            }
            if (codeLines.length > 5) {
              stdout.writeln('    ... (${codeLines.length - 5} more lines)');
            }
          }

          // Show container ID
          if (data['container_id'] != null) {
            stdout.writeln('  Container: ${data['container_id']}');
          }

          // Show output
          if (data['output'] != null) {
            stdout.writeln(
              '  Output: ${truncateValue(data['output'], maxLength: 200)}',
            );
          }
        }
      }
    }
  }
  print('\n');
}
