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
      'called "fib_sequence". Then create a CSV file called "fibonacci.csv" '
      'with two columns: index and value.';

  stdout.writeln('User: $prompt1');
  stdout.writeln('${agent1.displayName}: ');

  final history = <ChatMessage>[];
  String? containerId;
  await for (final chunk in agent1.sendStream(prompt1)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    dumpMetadataSpecialDelta(chunk.metadata, prefix: '\n');

    // Extract container_id from streaming metadata
    final cid = containerIdFromMetadata(chunk.metadata);
    if (cid != null) containerId = cid;
  }
  stdout.writeln();

  // Verify we got a container ID
  if (containerId == null) {
    throw StateError('No container_id found in streaming metadata');
  }

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

  String? session2ContainerId;
  await for (final chunk in agent2.sendStream(
    prompt2,
    history: history, // Pass conversation history here
  )) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    dumpMetadataSpecialDelta(chunk.metadata, prefix: '\n');

    // Extract container_id from streaming metadata
    final cid = containerIdFromMetadata(chunk.metadata);
    if (cid != null) session2ContainerId = cid;
  }
  stdout.writeln();

  // Verify container reuse by checking session 2 streaming metadata
  final sessions2ContainerId = session2ContainerId;

  if (sessions2ContainerId != containerId) {
    stdout.writeln(
      '❌ Container NOT reused: $containerId != $sessions2ContainerId',
    );
    return;
  } else {
    stdout.writeln('✅ Container reused: $containerId');
  }

  dumpFiles(history);
  dumpMessages(history);
  exit(0);
}

void dumpFiles(List<ChatMessage> history) {
  for (final msg in history) {
    for (final part in msg.parts) {
      if (part is DataPart) {
        // Use the actual filename from the DataPart (without path)
        final filename = part.name ?? 'unnamed_file';

        final file = File('tmp/$filename');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(part.bytes);
        stdout.writeln(
          '💾 Saved file: tmp/$filename (${part.bytes.length} bytes)',
        );
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

String? containerIdFromMetadata(Map<String, dynamic> metadata) {
  final ciEvents = metadata['code_interpreter'] as List?;
  if (ciEvents != null) {
    for (final event in ciEvents) {
      // Check for container_id at the top level (older synthetic events)
      if (event['container_id'] != null) {
        return event['container_id'] as String;
      }
      // Check for container_id nested in item (response.output_item.done
      // events)
      final item = event['item'];
      if (item is Map && item['container_id'] != null) {
        return item['container_id'] as String;
      }
    }
  }
  return null;
}
