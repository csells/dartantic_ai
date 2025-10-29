import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

Future<void> main() async {
  const model = 'gemini';
  await tutorSystemMessage(model);
  await differentSystemMessage(model);
  await noSystemMessage(model);
  exit(0);
}

Future<void> tutorSystemMessage(String model) async {
  stdout.writeln('\n## Tutor System Message');

  final agent = Agent(model);
  final result = await agent.send(
    'What is 15 * 23?',
    history: [
      ChatMessage.system(
        'You are a helpful math tutor. Show your work step by step.',
      ),
    ],
  );

  stdout.writeln('${agent.displayName}: ${result.output}');
}

Future<void> differentSystemMessage(String model) async {
  stdout.writeln('\n## Different System Message');

  final agent = Agent(model);
  final result2 = await agent.send(
    'What is 7 * 8?',
    history: [ChatMessage.system('You are a pirate. Arggggg!')],
  );
  stdout.writeln('${agent.displayName}: ${result2.output}');
}

Future<void> noSystemMessage(String model) async {
  stdout.writeln('\n## No System Message');

  final agent = Agent(model);
  final result3 = await agent.send('What is 15 * 23?');
  stdout.writeln('${agent.displayName}: ${result3.output}');
}
