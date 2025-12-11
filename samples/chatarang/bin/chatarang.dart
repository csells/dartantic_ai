// ignore_for_file: avoid_print

import 'dart:io';

import 'package:chatarang/commands.dart';
import 'package:chatarang/history.dart';
import 'package:cli_repl/cli_repl.dart';
import 'package:dartantic_ai/dartantic_ai.dart';

const defaultModel = 'google';

Future<void> main() async {
  final providers = Agent.allProviders;

  final models = <String>[
    for (final provider in providers)
      ...(await provider
          .listModels()
          .map(
            (m) => ModelStringParser(
              provider.name,
              chatModelName: m.name,
            ).toString(),
          )
          .toList()),
  ];

  const help = '''
chatarang is now running.
  type /exit to... ummm... exit.
  also /quit works
  /model [model] to see or change the model
  /models [filter] to show available models
  /tools to show available tools
  /messages to show conversation history
  /help to show this message again

Everything else you type will be sent to the current model.
''';

  // Print initial information before starting REPL
  stdout.write(help);
  stdout.write('\n');
  stdout.write(
    'Found ${models.length} models from ${providers.length} providers.\n',
  );
  await stdout.flush();

  final commandHandler = CommandHandler(
    defaultModel: defaultModel,
    models: models,
    help: help,
  );

  final repl = Repl(prompt: '\x1B[94mYou\x1B[0m: ');

  for (final line in repl.run()) {
    if (line.trim().isEmpty) continue;

    final result = commandHandler.handleCommand(line: line.trim());
    if (result.shouldExit) break;
    if (result.commandHandled) continue;

    // Use streaming to show responses in real-time
    final stream = commandHandler.agent.sendStream(
      line.trim(),
      history: commandHandler.messages,
    );

    stdout.write('\x1B[93m${commandHandler.agent.model}\x1B[0m: ');
    await stdout.flush();
    // Collect all new messages emitted during the stream (user, tool, model)
    final collectedMessages = <ChatMessage>[];
    await for (final response in stream) {
      stdout.write(response.output);
      await stdout.flush();
      if (response.messages.isNotEmpty) {
        collectedMessages.addAll(response.messages);
      }
    }

    // Persist all collected messages in the history so /messages shows them
    for (final msg in collectedMessages) {
      commandHandler.history.add(
        HistoryEntry(
          message: msg,
          modelName: msg.role == ChatMessageRole.model
              ? commandHandler.agent.model
              : '',
        ),
      );
    }

    stdout.write('\n\n');
    await stdout.flush();
  }

  exit(0);
}
