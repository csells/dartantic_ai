// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

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
    dumpMetadataSpecialDelta(chunk.metadata, prefix: '\n');
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
      'Create a plot showing how the ratio converges to the golden ratio. '
      'Save the plot as a PNG file called "golden_ratio.png".';

  stdout.writeln('User: $prompt2');
  stdout.write('${agent2.displayName}: ');

  await for (final chunk in agent2.sendStream(
    prompt2,
    history: history, // Pass conversation history here
  )) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    dumpMetadataSpecialDelta(chunk.metadata, prefix: '\n');
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

  dumpImages(history);
  dumpMessages(history);
}

void dumpImages(List<ChatMessage> history) {
  for (final msg in history) {
    for (final part in msg.parts) {
      if (part is DataPart && part.mimeType.startsWith('image/')) {
        dumpImage('Interpreter Image', 'image', part.bytes);
      }
    }
  }
}

void dumpMetadataSpecialDelta(
  Map<String, dynamic> metadata, {
  required String prefix,
}) {
  for (final entry in metadata.entries) {
    if (entry.key == 'code_interpreter' &&
        entry.value[0]['type'] == 'response.code_interpreter_call_code.delta') {
      stdout.write(entry.value[0]['delta']);
      return;
    }
  }

  dumpMetadata(metadata, prefix: prefix);
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
