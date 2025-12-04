import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main() async {
  // dude. no. "google:gemini-3-pro" and "openai-responses:gpt5.1-codex"
  // and "anthropic:claude-opus-4.5"
  // await Providers.anthropic.listModels().forEach((m) => print(m.name));
  // return;
  const model = 'anthropic:claude-opus-4-5';
  await singleTurnChat(model);
  await singleTurnChatStream(model);
  exit(0);
}

Future<void> singleTurnChat(String model) async {
  stdout.writeln('\n## Single Turn Chat');

  final agent = Agent(model);
  const prompt = 'What is the capital of England?';
  stdout.writeln('User: $prompt');
  final result = await agent.send(prompt);
  stdout.writeln('${agent.displayName}: ${result.output}');
  dumpMessages(result.messages);
}

Future<void> singleTurnChatStream(String model) async {
  stdout.writeln('\n## Single Turn Chat Streaming');

  final agent = Agent(model);
  final history = <ChatMessage>[];
  const prompt = 'Count from 1 to 5, one number at a time';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();
  dumpMessages(history);
}
