import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  // you can define your own OpenAI-compatible provider
  final fireworks = OpenAIProvider(
    name: 'fireworks',
    displayName: 'Fireworks',
    defaultModelNames: {
      ModelKind.chat: 'accounts/fireworks/models/llama-v3p1-8b-instruct',
    },
    baseUrl: Uri.parse('https://api.fireworks.ai/inference/v1'),
    apiKeyName: 'FIREWORKS_API_KEY',
  );

  // and you can register it like any other provider
  Providers.providerMap['fireworks'] = fireworks;

  // and use it like any other provider
  final agent = Agent('fireworks');
  final result = await agent.send(
    'What is the meaning to life, the universe, and everything?',
    history: [ChatMessage.system('provide short, snappy answers')],
  );
  stdout.writeln(result.output);
}
