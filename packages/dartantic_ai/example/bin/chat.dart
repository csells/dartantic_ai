import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'openai-responses';
  await multiTurnChat(model);
  await multiTurnChatStream(model);
  await multiTurnTypedChat(model);
  await multiTurnTypedChatStream(model);
  exit(0);
}

Future<void> multiTurnChat(String model) async {
  stdout.writeln('\n## Multi-Turn Chat');

  final chat = Chat(
    Agent(model, tools: [weatherTool, temperatureConverterTool]),
    history: [ChatMessage.system('You are a helpful weather assistant.')],
  );

  var prompt = "What's the Paris temperature in Fahrenheit?";
  stdout.writeln('User: $prompt');
  final result = await chat.send(prompt);
  stdout.writeln('${chat.displayName}: ${result.output.trim()}');
  dumpMessages(chat.history);

  prompt = 'Is that typical for this time of year?';
  stdout.writeln('User: $prompt');
  stdout.write('${chat.displayName}: ');
  await chat.sendStream(prompt).forEach((r) => stdout.write(r.output));
  dumpMessages(chat.history);
}

Future<void> multiTurnChatStream(String model) async {}

Future<void> multiTurnTypedChat(String model) async {
  stdout.writeln('\n## Multi-Turn Typed Chat');

  final chat = Chat(
    Agent(model, tools: [weatherTool, temperatureConverterTool]),
    history: [ChatMessage.system('You are a helpful weather assistant.')],
  );

  const prompt = 'Can you give me the current local time and temperature?';
  stdout.writeln('User: $prompt');
  final typedResult = await chat.sendFor<TimeAndTemperature>(
    prompt,
    outputSchema: TimeAndTemperature.schema,
    outputFromJson: TimeAndTemperature.fromJson,
  );

  stdout.writeln('${chat.displayName}: time = ${typedResult.output.time}');
  stdout.writeln(
    '${chat.displayName}: temperature = ${typedResult.output.temperature}°C',
  );
  dumpMessages(chat.history);
}

Future<void> multiTurnTypedChatStream(String model) async {}
