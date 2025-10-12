// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dotprompt_dart/dotprompt_dart.dart';

void main() async {
  final dotPrompt = DotPrompt('''
---
model: gemini
input:
  default:
    length: 3
    text: "The quick brown fox jumps over the lazy dog."
---
Summarize this in {{length}} words: {{text}}
''');

  final prompt = dotPrompt.render();
  final agent = Agent(dotPrompt.frontMatter.model!);
  print(agent.displayName);
  await agent.sendStream(prompt).forEach((r) => stdout.write(r.output));
  stdout.writeln();
  exit(0);
}
