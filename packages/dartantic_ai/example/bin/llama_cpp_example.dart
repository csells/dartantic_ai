import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

/// Example of using LlamaCpp provider with a local GGUF model.
///
/// Before running this example:
/// 1. Build the llama.cpp shared library from llama_cpp_dart package:
///    - The llama_cpp_dart package includes llama.cpp as a submodule
///    - Follow build instructions: https://github.com/netdur/llama_cpp_dart/blob/main/BUILD.md
///    - For macOS: Run darwin/build.sh (requires Apple Developer Team ID)
///    - Built libraries will be in bin/MAC_ARM64/ (or appropriate platform dir)
///    - Alternatively: Build llama.cpp directly from https://github.com/ggml-org/llama.cpp
/// 2. Download a GGUF model file from Hugging Face
///    https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF
/// 3. Update the modelPath and libraryPath variables below
void main() async {
  // Update this path to point to your GGUF model file
  const modelPath = '/Users/csells/temp/llama-2-7b-chat.Q4_K_M.gguf';

  // Set the path to the llama.cpp shared library. After building using
  // llama_cpp_dart's build scripts, the library will be at:
  // - macOS ARM64: [llama_cpp_dart_package]/bin/MAC_ARM64/libllama.dylib
  // - iOS: [llama_cpp_dart_package]/bin/OS64/libllama.dylib Or use an absolute
  //   path to a library you built separately
  const libraryPath = 'path/to/libllama.dylib'; // Update this path

  // Check if model file exists
  if (!File(modelPath).existsSync()) {
    stdout.writeln(
      'Error: Model file not found at $modelPath\n'
      'Please download a GGUF model file and update the modelPath variable.',
    );
    exit(1);
  }

  // Check if library file exists
  if (!File(libraryPath).existsSync()) {
    stdout.writeln(
      'Error: llama.cpp library not found at $libraryPath\n'
      'Please update the libraryPath variable or build the library.',
    );
    exit(1);
  }

  await llamaCppChat(modelPath, libraryPath);
  exit(0);
}

Future<void> llamaCppChat(String modelPath, String libraryPath) async {
  stdout.writeln('\n## LlamaCpp Local Model Chat');

  // Create provider with library path and model path
  final provider = LlamaCppProvider(
    modelPath: modelPath,
    libraryPath: libraryPath,
  );

  // Create agent with the provider
  final agent = Agent.forProvider(provider);

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
