// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('OpenAI Responses: Image Generation Demo\n');

  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.imageGeneration},
      // Request partial images, low quality, small size
      imageGenerationConfig: ImageGenerationConfig(
        partialImages: 3,
        quality: ImageGenerationQuality.low,
        size: ImageGenerationSize.square256,
      ),
    ),
  );

  const prompt =
      'Generate a simple, minimalist logo for a fictional '
      'AI startup called "NeuralFlow". Use geometric shapes and '
      'a modern color palette with blue and purple gradients.';

  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    // dumpMetadata(chunk.metadata, prefix: '\n');
    _dumpPartialImages(chunk.metadata);
  }
  stdout.writeln();

  // Final image arrives as a DataPart in the message history
  dumpAssetsFromHistory(history, 'tmp', fallbackPrefix: 'generated_image');

  exit(0);
}

/// Saves partial/progressive images from streaming metadata.
void _dumpPartialImages(Map<String, dynamic> metadata) {
  final imageEvents = metadata['image_generation'] as List?;
  if (imageEvents == null) return;

  for (final event in imageEvents) {
    final partial = event['partial_image_b64'];
    if (partial == null) continue;

    final base64 = partial as String;
    final index = event['partial_image_index'] as int? ?? 0;
    final bytes = base64Decode(base64);
    final mimeType = Part.mimeType('', headerBytes: bytes);
    final extension = Part.extensionFromMimeType(mimeType)!;
    final part = DataPart(
      bytes,
      mimeType: mimeType,
      name: 'partial_$index.$extension',
    );
    dumpAssets([part], 'tmp', fallbackPrefix: 'partial');
  }
}
