import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

/// Example of using LlamaCpp provider with a local GGUF model.
///
/// Before running this example:
/// 1. Download a GGUF model file (e.g., from Hugging Face)
/// 2. Update the modelPath variable below with the path to your model
/// 3. Ensure the llama.cpp shared library is available
///
/// Example model download:
/// https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF
void main() async {
  // Update this path to point to your GGUF model file
  const modelPath = '/Users/csells/temp/llama-2-7b-chat.Q4_K_M.gguf';

  // Check if model file exists
  if (!File(modelPath).existsSync()) {
    stdout.writeln(
      'Error: Model file not found at $modelPath\n'
      'Please download a GGUF model file and update the modelPath variable.',
    );
    exit(1);
  }

  await llamaCppChat(modelPath);
  exit(0);
}

Future<void> llamaCppChat(String modelPath) async {
  stdout.writeln('\n## LlamaCpp Local Model Chat');

  // Create agent with llama_cpp provider
  // Use query parameter format for file paths to preserve absolute paths
  final agent = Agent('llama_cpp?chat=$modelPath');

  const prompt = 'What is the capital of France?';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');

  // Stream the response
  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }

  stdout.writeln();
  dumpMessages(history);
}
