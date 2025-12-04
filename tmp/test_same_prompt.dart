import 'dart:io';
import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  // EXACT same prompt as server-side example
  const prompt = 'Calculate the first 10 Fibonacci numbers and store them in a '
      'variable called "fib_sequence". Then create a CSV file called '
      '"fibonacci.csv" with two columns: index and value.';

  stdout.writeln('=== Test 1: Via sendStream (like server-side example) ===');
  final agent1 = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      serverSideTools: {OpenAIServerSideTool.codeInterpreter},
    ),
  );
  final history = <ChatMessage>[];
  await for (final chunk in agent1.sendStream(prompt)) {
    history.addAll(chunk.messages);
  }
  final sendDataParts = history.expand((m) => m.parts).whereType<DataPart>();
  stdout.writeln('sendStream result: ${sendDataParts.length} DataParts');
  for (final dp in sendDataParts) {
    stdout.writeln('  - ${dp.name} (${dp.mimeType})');
  }

  stdout.writeln('\n=== Test 2: Via generateMedia (media gen model) ===');
  final agent2 = Agent('openai-responses');
  final result = await agent2.generateMedia(
    prompt,
    mimeTypes: const ['text/csv'],
  );
  stdout.writeln('generateMedia result: ${result.assets.length} assets');
  for (final asset in result.assets) {
    if (asset is DataPart) {
      stdout.writeln('  - ${asset.name} (${asset.mimeType})');
    }
  }

  exit(0);
}
