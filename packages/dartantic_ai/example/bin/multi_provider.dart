// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/src/example_tools.dart';

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

  stdout.writeln('\n## Multi-Provider Conversation\n');
  final history = <ChatMessage>[ChatMessage.system('Be brief.')];
  await _promptAgent(
    Agent('google', displayName: 'Google'),
    'Hi! My name is Alice and I work as a software engineer in Seattle. '
    'I love hiking and coffee.',
    history,
  );

  await _promptAgent(
    Agent('anthropic', displayName: 'Claude'),
    'What do you remember about me?',
    history,
  );

  await _promptAgent(
    Agent(
      'openai',
      displayName: 'OpenAI',
      tools: [weatherTool, temperatureTool],
    ),
    'Can you check the weather where I live?',
    history,
  );

  await _promptAgent(
    Agent(
      'google:gemini-3-pro-preview',
      displayName: 'Google Gemini 3 Pro Preview',
    ),
    'What outdoor activities would you recommend for me?',
    history,
  );

  await _promptAgent(
    Agent('openai-responses', displayName: 'OpenAI Responses'),
    'Can you summarize our conversation?',
    history,
  );

  exit(0);
}

Future<void> _promptAgent(
  Agent agent,
  String prompt,
  List<ChatMessage> history,
) async {
  final userColor = entityColor('user');
  stdout.writeln('$bold${userColor}User:$reset $userColor$prompt$reset');
  final agentColor = entityColor(agent.model.split(':')[0]);
  stdout.write('$bold$agentColor${agent.displayName}: $reset');
  await agent.sendStream(prompt, history: history).forEach((chunk) {
    stdout.write('$agentColor${chunk.output}$reset');
    history.addAll(chunk.messages);
  });
  stdout.writeln('\n\n');
}

// ANSI color codes
const reset = '\x1B[0m';
const bold = '\x1B[1m';
const cyan = '\x1B[36m';
const yellow = '\x1B[33m';
const green = '\x1B[32m';
const magenta = '\x1B[35m';
const blue = '\x1B[34m';

// Entity colors
String entityColor(String entity) => switch (entity) {
  _ when entity.contains('user') => cyan,
  _ when entity.contains('google') => green,
  _ when entity.contains('anthropic') => magenta,
  _ when entity.contains('openai') => blue,
  _ when entity.contains('openai-responses') => yellow,
  _ => throw Exception('Unknown entity: $entity'),
};
