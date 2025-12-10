import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'gemini';
  await multiTurnChat(model);
  await multiTurnChatStream(model);
  await multiToolTypedChat(model);
  await multiToolTypedChatStream(model);
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

  prompt = 'Is that a good time for shorts?';
  stdout.writeln('User: $prompt');
  final result2 = await chat.send(prompt);
  stdout.writeln('${chat.displayName}: ${result2.output.trim()}');
}

Future<void> multiTurnChatStream(String model) async {
  stdout.writeln('\n## Multi-Turn Chat Streaming');

  final chat = Chat(
    Agent(model, tools: [weatherTool, temperatureConverterTool]),
    history: [ChatMessage.system('You are a helpful weather assistant.')],
  );

  var prompt = "What's the Paris temperature in Fahrenheit?";
  stdout.writeln('User: $prompt');
  stdout.write('${chat.displayName}: ');
  await chat.sendStream(prompt).forEach((r) => stdout.write(r.output));
  stdout.writeln();

  prompt = 'Is that a good time for shorts?';
  stdout.writeln('User: $prompt');
  stdout.write('${chat.displayName}: ');
  await chat.sendStream(prompt).forEach((r) => stdout.write(r.output));
  stdout.writeln();
}

Future<void> multiToolTypedChat(String model) async {
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

  stdout.writeln('${chat.displayName}: time= ${typedResult.output.time}');
  stdout.writeln(
    '${chat.displayName}: temperature= ${typedResult.output.temperature}°C',
  );
}

Future<void> multiToolTypedChatStream(String model) async {
  stdout.writeln('\n## Multi-Turn Typed Chat Streaming');

  final chat = Chat(
    Agent(model, tools: [weatherTool, temperatureConverterTool]),
    history: [ChatMessage.system('You are a helpful weather assistant.')],
  );

  const prompt = 'Can you give me the current local time and temperature?';
  stdout.writeln('User: $prompt');
  final jsonBuffer = StringBuffer();
  await chat
      .sendStream(prompt, outputSchema: TimeAndTemperature.schema)
      .forEach((r) {
        jsonBuffer.write(r.output);
        stdout.write(r.output);
      });
  stdout.writeln();

  final tnt = TimeAndTemperature.fromJson(jsonDecode(jsonBuffer.toString()));
  stdout.writeln('${chat.displayName}: time= ${tnt.time}');
  stdout.writeln('${chat.displayName}: temperature= ${tnt.temperature}°C');
}
