// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'history.dart';
import 'tools.dart';

class HandleCommandResult {
  HandleCommandResult({this.shouldExit = false, this.commandHandled = true});
  final bool shouldExit;
  final bool commandHandled;
}

class CommandHandler {
  CommandHandler({
    required String defaultModel,
    required this.models,
    required this.help,
  }) : agent = _createAgent(defaultModel),
       history = List<HistoryEntry>.from([
         HistoryEntry(
           modelName: '',
           message: ChatMessage.system(_systemPrompt),
         ),
       ]);

  Agent agent;
  late final List<HistoryEntry> history;
  final List<String> models;
  final String help;

  List<ChatMessage> get messages => history.map((e) => e.message).toList();

  static Agent _createAgent(String model) => Agent(model, tools: tools);

  static String get _systemPrompt {
    final toolDescriptions = StringBuffer();
    for (final tool in tools) {
      toolDescriptions.write('Tool: ${tool.name}\n');
      toolDescriptions.write('- Description: ${tool.description}\n');
      toolDescriptions.write('- Input schema: ${tool.inputSchema}\n');
      toolDescriptions.write('\n');
    }

    return '''
You are a helpful AI assistant with access to tools that can help you provide better responses. 

IMPORTANT: Before asking the user for additional information, always consider if you can use your available tools to gather the information yourself. Carefully review each tool to see if it can help with the user's request.

Available tools:

$toolDescriptions

When responding:
1. First, carefully consider each available tool by name, description, and input schema
2. If any tool can help answer the user's question or request, use it
3. Only ask the user for additional information if none of your tools can provide what's needed
4. Be proactive in using tools to provide comprehensive and helpful responses
''';
  }

  void _setModel(String newModel) {
    agent = _createAgent(newModel);
  }

  HandleCommandResult handleCommand({required String line}) {
    if (!line.startsWith('/')) {
      return HandleCommandResult(commandHandled: false);
    }

    final parts = line.split(' ');
    final command = parts.first.toLowerCase();
    final args = parts.sublist(1);

    if (command == '/exit' || command == '/quit') {
      return HandleCommandResult(shouldExit: true);
    }

    switch (command) {
      case '/help':
        print(help);
        return HandleCommandResult();

      case '/models':
        final filteredModels = models
            .where((m) => args.every((arg) => m.contains(arg)))
            .toList();
        filteredModels.forEach(print);
        if (args.isNotEmpty) {
          print(
            '\nFound ${filteredModels.length} models matching your filter.',
          );
        } else {
          print('\nFound ${models.length} models.');
        }
        return HandleCommandResult();

      case '/tools':
        for (final tool in tools) {
          print(tool.name);
        }
        print('\nFound ${tools.length} tools.');
        return HandleCommandResult();

      case '/messages':
        print('');
        if (history.isEmpty) {
          print('No messages yet.');
        } else {
          for (final entry in history) {
            final message = entry.message;
            final role = message.role;
            switch (role) {
              case ChatMessageRole.user:
                // A user message can contain text and/or tool results to be
                // sent to the model. We iterate through the parts to display
                // them in order.
                for (final part in message.parts) {
                  if (part is TextPart) {
                    if (part.text.isNotEmpty) {
                      print('\x1B[94mYou\x1B[0m: ${part.text}');
                    }
                  } else if (part is ToolPart) {
                    if (part.kind == ToolPartKind.result) {
                      final result = const JsonEncoder.withIndent(
                        '  ',
                      ).convert(part.result);

                      var resultToShow = result;
                      if (resultToShow.length > 256) {
                        resultToShow = '${resultToShow.substring(0, 256)}...';
                      }

                      print(
                        '\x1B[96mTool.result\x1B[0m: ${part.name}: '
                        '$resultToShow',
                      );
                    }
                  }
                }
              case ChatMessageRole.model:
                final modelName = entry.modelName;
                for (final part in message.parts) {
                  if (part is TextPart) {
                    print('\x1B[93m$modelName\x1B[0m: ${part.text}');
                  } else if (part is ToolPart) {
                    if (part.kind == ToolPartKind.call) {
                      final args = const JsonEncoder.withIndent(
                        '  ',
                      ).convert(part.arguments);
                      print('\x1B[95mTool.call\x1B[0m: ${part.name}($args)');
                    }
                  }
                }
              case ChatMessageRole.system:
                // system prompt
                print(
                  '\x1B[91m${role.name.toUpperCase()}\x1B[0m: '
                  '${message.text}',
                );
            }
          }
        }
        return HandleCommandResult();

      case '/clear':
        history.clear();
        print("You're chatting with ${agent.model}");
        return HandleCommandResult();

      case '/model':
        if (args.isEmpty) {
          print('Current model: ${agent.model}');
        } else {
          final newModel = args.join(':');
          if (models.contains(newModel)) {
            try {
              _setModel(newModel);
              print('Model set to: $newModel');
            } on Exception catch (ex) {
              print('Error setting model: $ex');
            }
          } else {
            print('Unknown model: $newModel. Use /models to see models.');
          }
        }
        return HandleCommandResult();

      default:
        print('Unknown command: $command');
        return HandleCommandResult();
    }
  }
}
