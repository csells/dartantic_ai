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
  Agent.environment['GEMINI_API_KEY'] = Platform.environment['GEMINI_API_KEY']!;

  print('Multi-Provider Conversation Demo\n');
  final history = <ChatMessage>[];

  // Step 1: Start with Gemini
  print('═══ Step 1: Starting with Gemini ═══');
  final gemini = Agent('google');
  final result1 = await gemini.send(
    'Hi! My name is Alice and I work as a software engineer in Seattle. '
    'I love hiking and coffee.',
  );
  history.addAll(result1.messages);
  print('Gemini: ${result1.output}\n');

  // Step 2: Continue with Claude
  print('═══ Step 2: Switching to Claude ═══');
  final claude = Agent('anthropic');
  final result2 = await claude.send(
    'What do you remember about me?',
    history: history,
  );
  history.addAll(result2.messages);
  print('Claude: ${result2.output}\n');

  // Step 3: Use OpenAI with tools
  print('═══ Step 3: OpenAI with Tools ═══');
  final openai = Agent(
    'openai-responses',
    tools: [weatherTool, temperatureTool],
  );
  final result3 = await openai.send(
    'Can you check the weather where I live?',
    history: history,
  );
  history.addAll(result3.messages);
  print('OpenAI: ${result3.output}\n');

  // Step 4: Back to Gemini to reference the tool results
  print('═══ Step 4: Back to Gemini ═══');
  final gemini2 = Agent('google');
  final result4 = await gemini2.send(
    'Based on the weather, what outdoor activities would you recommend '
    'for someone who loves hiking?',
    history: history,
  );
  history.addAll(result4.messages);
  print('Gemini: ${result4.output}\n');

  // Step 5: Use Claude for a final summary
  print('═══ Step 5: Claude for Summary ═══');
  final claude2 = Agent('anthropic');
  final result5 = await claude2.send(
    'Can you summarize our entire conversation, including what you '
    'learned about me and any information we looked up?',
    history: history,
  );
  history.addAll(result5.messages);
  print('Claude: ${result5.output}\n');

  // Show the complete message history
  print('═══ Complete Message History ═══');
  dumpMessages(history);

  print('Total messages: ${history.length}');
  print('Provider sequence:');
  var lastProvider = '';
  for (var i = 0; i < history.length; i += 2) {
    if (i < result1.messages.length) {
      if (lastProvider != 'Gemini') print('  → Gemini');
      lastProvider = 'Gemini';
    } else if (i < result1.messages.length + result2.messages.length) {
      if (lastProvider != 'Claude') print('  → Claude');
      lastProvider = 'Claude';
    } else if (i <
        result1.messages.length +
            result2.messages.length +
            result3.messages.length) {
      if (lastProvider != 'OpenAI') print('  → OpenAI (with tools)');
      lastProvider = 'OpenAI';
    } else if (i <
        result1.messages.length +
            result2.messages.length +
            result3.messages.length +
            result4.messages.length) {
      if (lastProvider != 'Gemini') print('  → Gemini');
      lastProvider = 'Gemini';
    } else {
      if (lastProvider != 'Claude') print('  → Claude');
      lastProvider = 'Claude';
    }
  }
}
