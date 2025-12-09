// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  print('=== OpenAI-Compatible Providers ===\n');

  Agent.providerFactories['together'] = () => OpenAIProvider(
    name: 'together',
    displayName: 'Together AI',
    defaultModelNames: {
      ModelKind.chat: 'meta-llama/Llama-3.2-3B-Instruct-Turbo',
    },
    baseUrl: Uri.parse('https://api.together.xyz/v1'),
    apiKeyName: 'TOGETHER_API_KEY',
  );

  Agent.providerFactories['google-openai'] = () => OpenAIProvider(
    name: 'google-openai',
    displayName: 'Google AI (OpenAI-compatible)',
    defaultModelNames: {
      ModelKind.chat: 'gemini-2.5-flash',
      ModelKind.embeddings: 'text-embedding-004',
    },
    baseUrl: Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/openai',
    ),
    apiKeyName: 'GEMINI_API_KEY',
  );

  Agent.providerFactories['ollama-openai'] = () => OpenAIProvider(
    name: 'ollama-openai',
    displayName: 'Ollama (OpenAI-compatible)',
    defaultModelNames: {ModelKind.chat: 'llama3.2'},
    baseUrl: Uri.parse('http://localhost:11434/v1'),
    apiKeyName: null,
  );

  final agents = [
    Agent('openrouter'),
    Agent('together'),
    Agent('google-openai'),
    Agent('ollama-openai'),
  ];

  final history = <ChatMessage>[];
  for (final agent in agents) {
    final prompt =
        'You are ${agent.displayName}. '
        'Introduce yourself to the others, addressing them by name. '
        'Be concise and to the point.';
    stdout.writeln('User: $prompt');
    stdout.write('${agent.displayName}: ');
    await for (final chunk in agent.sendStream(prompt, history: history)) {
      stdout.write(chunk.output);
      history.addAll(chunk.messages);
    }
    stdout.writeln();
    stdout.writeln();
  }

  exit(0);
}
