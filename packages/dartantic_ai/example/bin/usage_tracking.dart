import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

void main() async {
  const model = 'gemini';
  await usage(model);
  await streamingUsage(model);
  exit(0);
}

Future<void> usage(String model) async {
  final agent = Agent(model);
  stdout.writeln('\n## ${agent.displayName} Usage');

  const prompt = 'Write a haiku about programming';
  stdout.writeln('User: $prompt');
  final result = await agent.send(prompt);
  stdout.writeln('${agent.displayName}: ${result.output}');

  dumpUsage(result.usage);
}

Future<void> streamingUsage(String model) async {
  final agent = Agent(model);
  stdout.writeln('\n## ${agent.displayName} Streaming Usage');

  const prompt = 'Write a haiku about programming';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');

  LanguageModelUsage? streamUsage;
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    if (chunk.usage != null) {
      assert(streamUsage == null, 'Usage reported multiple times in stream');
      streamUsage = chunk.usage;
    }
  }
  stdout.writeln();

  dumpUsage(streamUsage);
}
