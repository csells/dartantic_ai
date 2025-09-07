// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

Future<void> main() async {
  print('=== Server-Side Tools Example ===\n');

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatOptions(
      serverSideTools: {
        OpenAIServerSideTool.webSearch,
        OpenAIServerSideTool.imageGeneration,
      },
      // Leave toolChoice on provider default ('auto')
    ),
  );

  stdout.writeln('Prompt: Generate a small logo and cite your sources.');
  stdout.write('Model: ');

  await for (final chunk in agent.sendStream(
    'Generate an actual image (PNG) using the image generation tool: a simple '
    'black-and-white logo for a cafe named "Bean & Byte". Do not merely '
    'describe the image—return the image artifact itself. Then use web search '
    'to find two links published today about minimalist logo design trends. '
    'Keep the search results brief.',
  )) {
    // Streamed text
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Dump all metadata generically with truncation
    dumpMetadata(chunk.metadata, prefix: '\n', maxLength: 512);

    // Media parts (e.g., image_generation): LinkPart or DataPart
    for (final m in chunk.messages) {
      if (m.role != ChatMessageRole.model) continue;
      for (final p in m.parts) {
        if (p is LinkPart) {
          stdout.writeln('\n[image] ${p.url}');
        } else if (p is DataPart && p.mimeType.startsWith('image/')) {
          // Write image to a temp file
          final out = File(
            'tmp/server_side_tools_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          out.createSync(recursive: true);
          out.writeAsBytesSync(p.bytes);

          // Create base64 data URL for markdown display
          final b64 = base64.encode(p.bytes);
          final dataUrl = 'data:${p.mimeType};base64,$b64';

          stdout.writeln('\n[image] Saved to: ${out.path}');
          stdout.writeln('![Generated Image]($dataUrl)');
        }
      }
    }
  }
}
