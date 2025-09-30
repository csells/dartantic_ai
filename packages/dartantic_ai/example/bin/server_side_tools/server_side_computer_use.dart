// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('🖥️ Computer Use Demo');
  stdout.writeln('Note: Computer use requires special setup and permissions.');
  stdout.writeln(
    'This feature requires enterprise access and '
    'additional configuration.',
  );
  stdout.writeln('See docs/server-side-tools/computer-use.mdx for details.');

  // Computer use is typically not available without special permissions
  stdout.writeln(
    'This demo demonstrates browser/desktop control capabilities.',
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

  stdout.writeln('Prompt: $prompt');
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
            stdout.writeln('  Target: ${clipWithNull(data['target'])}');
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
