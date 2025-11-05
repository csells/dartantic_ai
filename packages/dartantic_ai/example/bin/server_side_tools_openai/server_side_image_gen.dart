// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('🎨 Image Generation Demo\n');
  stdout.writeln('This demo generates images from text descriptions.\n');

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
    dumpMetadata(chunk.metadata, prefix: '\n');
    dumpPartialImages(chunk.metadata);
  }
  stdout.writeln();

  // Final image arrives as a DataPart in the model's response
  final imagePart = history.last.parts.whereType<DataPart>().singleWhere(
    (p) => p.mimeType.startsWith('image/'),
  );
  dumpImage('Final', 'final_image', imagePart.bytes);

  dumpMessages(history);
}

void dumpPartialImages(Map<String, dynamic> metadata) {
  final imageEvents = metadata['image_generation'] as List?;
  if (imageEvents != null) {
    for (final event in imageEvents) {
      // Progressive/partial images show intermediate render stages
      if (event['partial_image_b64'] != null) {
        final base64 = event['partial_image_b64']! as String;
        final index = event['partial_image_index']! as int;
        dumpImage('Partial', 'partial_image_$index', base64Decode(base64));
      }
    }
  }
}
