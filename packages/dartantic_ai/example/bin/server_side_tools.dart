// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

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
    'describe the image—return the image artifact itself. Then briefly cite '
    'two web sources about minimalist logo trends.',
  )) {
    // Streamed text
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);

    // Observability: web search
    final web = chunk.metadata['web_search'];
    if (web != null) {
      stdout.writeln('\n[web_search/${web['stage']}] ${web['data']}');
    }

    // Observability: code interpreter
    final ci = chunk.metadata['code_interpreter'];
    if (ci != null) {
      stdout.writeln('\n[code_interpreter/${ci['stage']}] ${ci['data']}');
    }

    // Observability: image generation
    final ig = chunk.metadata['image_generation'];
    if (ig != null) {
      stdout.writeln('\n[image_generation/${ig['stage']}] ${ig['data']}');
    }

    // Media parts (e.g., image_generation): LinkPart or DataPart
    for (final m in chunk.messages) {
      if (m.role != ChatMessageRole.model) continue;
      for (final p in m.parts) {
        if (p is LinkPart) {
          stdout.writeln('\n[image] url: ${p.url}');
        } else if (p is DataPart && p.mimeType.startsWith('image/')) {
          // Write image to a temp file and also emit Markdown data URL
          final out = File(
            'tmp/server_side_tools_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          out.createSync(recursive: true);
          out.writeAsBytesSync(p.bytes);

          // Emit a Markdown-friendly data URL for renderers that support it
          final b64 = base64.encode(p.bytes);
          final dataUrl = 'data:${p.mimeType};base64,$b64';
          stdout.writeln(
            '\n[image] bytes: ${p.bytes.length} (${p.mimeType}) -> ${out.path}',
          );
          stdout.writeln('\n![generated]($dataUrl)\n');
        }
      }
    }
  }

  stdout.writeln('\n\nDone.');
}
