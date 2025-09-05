// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  var chat = Chat(
    Agent('gemini', tools: [weatherTool, temperatureConverterTool]),
    history: [ChatMessage.system('You are a helpful weather assistant.')],
  );

  // multi-tool use w/ openai
  var prompt = "What's the Paris temperature in Fahrenheit?";
  print('user: $prompt');
  final result = await chat.send(prompt);
  print('${chat.displayName}: ${result.output.trim()}');
  dumpMessages(chat.history);
  print('');

  // multi-turn chat using context and streaming output w/ gemini
  chat = Chat(
    Agent('openai-responses', tools: [weatherTool, temperatureConverterTool]),
    history: chat.history,
  );
  prompt = 'Is that typical for this time of year?';
  print('user: $prompt');
  stdout.write('${chat.displayName}: ');
  await dumpStream(chat.sendStream(prompt));
  dumpMessages(chat.history);
  print('');

  // typed output and tool use w/ anthropic
  chat = Chat(
    Agent('anthropic', tools: [weatherTool, temperatureConverterTool]),
    history: chat.history,
  );
  prompt = 'Can you give me the current local time and temperature?';
  print('user: $prompt');
  final typedResult = await chat.sendFor<TimeAndTemperature>(
    prompt,
    outputSchema: TimeAndTemperature.schema,
    outputFromJson: TimeAndTemperature.fromJson,
  );

  print('${chat.displayName}.time: ${typedResult.output.time}');
  print('${chat.displayName}.temperature: ${typedResult.output.temperature}°C');
  dumpMessages(chat.history);
  print('');

  exit(0);
}
