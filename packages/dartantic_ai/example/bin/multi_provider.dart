// ignore_for_file: avoid_print

import 'dart:io' show Platform;

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  // Example: Setting API keys programmatically via Agent.environment
  // By default, Agent.environment will be checked first and on platforms with
  // an environment (i.e. not web), the fallback will be Platform.environment,
  // so this code is unnecessary. But it does show how you can put stuff into
  // Agent.environment for environments that don't already have an environment
  // setup for your use, e.g. the web, taking API keys from a database, etc.
  //
  // Note: This example copies from Platform.environment to demonstrate the
  // feature while still working with your existing environment setup.
  Agent.environment['OPENAI_API_KEY'] = Platform.environment['OPENAI_API_KEY']!;

  final history = <ChatMessage>[];

  // agent 1
  final agent1 = Agent('google');
  print('## Starting with ${agent1.displayName}');
  final result1 = await agent1.send(
    'Hi! My name is Alice and I work as a software engineer in Seattle. '
    'I love hiking and coffee.',
  );
  history.addAll(result1.messages);
  print('${agent1.displayName}: ${result1.output}\n');

  // agent 2
  final agent2 = Agent('anthropic');
  print('## Switching to ${agent2.displayName}');
  final result2 = await agent2.send(
    'What do you remember about me?',
    history: history,
  );
  history.addAll(result2.messages);
  print('${agent2.displayName}: ${result2.output}\n');

  // agent 3
  final agent3 = Agent('openai', tools: [weatherTool, temperatureTool]);
  print('## Using ${agent3.displayName} with tools');
  final result3 = await agent3.send(
    'Can you check the weather where I live?',
    history: history,
  );
  history.addAll(result3.messages);
  print('${agent3.displayName}: ${result3.output}\n');

  // agent 4
  final agent4 = Agent('google');
  print('## Back to ${agent4.displayName} to reference the tool results');
  final result4 = await agent4.send(
    'Based on the weather, what outdoor activities would you recommend for me?',
    history: history,
  );
  history.addAll(result4.messages);
  print('${agent4.displayName}: ${result4.output}\n');

  // agent 5
  final agent5 = Agent('openai-responses');
  print('## Using ${agent5.displayName} for a final summary');
  final result5 = await agent5.send(
    'Can you summarize our conversation?',
    history: history,
  );
  history.addAll(result5.messages);
  print('${agent5.displayName}: ${result5.output}\n');

  print('## Message History');
  print('Total messages: ${history.length}');
  dumpMessages(history);

  print('## Provider sequence:');
  print('  → ${agent1.displayName}');
  print('  → ${agent2.displayName}');
  print('  → ${agent3.displayName}');
  print('  → ${agent4.displayName}');
  print('  → ${agent5.displayName}');
}
