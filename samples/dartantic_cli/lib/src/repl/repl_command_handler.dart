// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'history_entry.dart';

/// Result of handling a slash command.
class HandleCommandResult {
  /// Creates a command result.
  HandleCommandResult({this.shouldExit = false, this.commandHandled = true});

  /// Whether the REPL should exit.
  final bool shouldExit;

  /// Whether a command was handled (false if input was not a command).
  final bool commandHandled;
}

/// Handles slash commands within a REPL session.
class ReplCommandHandler {
  /// Creates a command handler.
  ReplCommandHandler({
    required this.help,
    required this.getAgent,
    required this.getHistory,
    required this.getTools,
    required this.getSystemPrompt,
    required this.onClearHistory,
    required this.onSetAgent,
    required this.onSetSystemPrompt,
    required this.onToggleVerbose,
    required this.onToggleThinking,
    required this.isVerbose,
    required this.isThinkingEnabled,
    required this.noColor,
  });

  /// Help text to display.
  final String help;

  /// Gets the current agent.
  final Agent Function() getAgent;

  /// Gets the current conversation history.
  final List<HistoryEntry> Function() getHistory;

  /// Gets the current list of tools.
  final List<Tool> Function() getTools;

  /// Gets the current system prompt.
  final String? Function() getSystemPrompt;

  /// Called when history should be cleared.
  final void Function() onClearHistory;

  /// Called when agent should be changed.
  final Future<bool> Function(String agentName) onSetAgent;

  /// Called when system prompt should be changed.
  final void Function(String prompt) onSetSystemPrompt;

  /// Called to toggle verbose mode.
  final void Function() onToggleVerbose;

  /// Called to toggle thinking display.
  final void Function() onToggleThinking;

  /// Returns whether verbose mode is enabled.
  final bool Function() isVerbose;

  /// Returns whether thinking display is enabled.
  final bool Function() isThinkingEnabled;

  /// Whether color output is disabled.
  final bool noColor;

  /// Handles a potential slash command.
  ///
  /// Returns a result indicating whether a command was handled and whether
  /// the REPL should exit.
  Future<HandleCommandResult> handleCommand({required String line}) async {
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
        _printHelp();
        return HandleCommandResult();

      case '/models':
        await _handleModels(args);
        return HandleCommandResult();

      case '/tools':
        _handleTools();
        return HandleCommandResult();

      case '/messages':
        _handleMessages();
        return HandleCommandResult();

      case '/clear':
        _handleClear();
        return HandleCommandResult();

      case '/model':
        await _handleModel(args);
        return HandleCommandResult();

      case '/system':
        _handleSystem(args);
        return HandleCommandResult();

      case '/verbose':
        _handleVerbose();
        return HandleCommandResult();

      case '/thinking':
        _handleThinking();
        return HandleCommandResult();

      default:
        _printError('Unknown command: $command. Type /help for available commands.');
        return HandleCommandResult();
    }
  }

  void _printHelp() {
    print(help);
  }

  Future<void> _handleModels(List<String> args) async {
    final agent = getAgent();
    try {
      final models = await agent.listModels().toList();
      final filteredModels = models
          .where((m) => args.every((arg) => m.name.contains(arg)))
          .toList();

      for (final model in filteredModels) {
        print(model.name);
      }

      if (args.isNotEmpty) {
        print(
          '\nFound ${filteredModels.length} models matching your filter.',
        );
      } else {
        print('\nFound ${models.length} models.');
      }
    } on Exception catch (e) {
      _printError('Failed to list models: $e');
    }
  }

  void _handleTools() {
    final tools = getTools();
    if (tools.isEmpty) {
      print('No MCP tools configured for this agent.');
      return;
    }

    for (final tool in tools) {
      if (noColor) {
        print('${tool.name}');
      } else {
        print('\x1B[95m${tool.name}\x1B[0m');
      }
      if (tool.description.isNotEmpty) {
        print('  ${tool.description}');
      }
    }
    print('\nFound ${tools.length} MCP tools.');
  }

  void _handleMessages() {
    final history = getHistory();
    print('');
    if (history.isEmpty) {
      print('No messages yet.');
    } else {
      for (final entry in history) {
        _printHistoryEntry(entry);
      }
    }
  }

  void _printHistoryEntry(HistoryEntry entry) {
    final message = entry.message;
    final role = message.role;

    switch (role) {
      case ChatMessageRole.user:
        for (final part in message.parts) {
          if (part is TextPart) {
            if (part.text.isNotEmpty) {
              _printColored('You', part.text, '\x1B[94m');
            }
          } else if (part is ToolPart && part.kind == ToolPartKind.result) {
            final result = const JsonEncoder.withIndent('  ').convert(
              part.result,
            );
            var resultToShow = result;
            if (resultToShow.length > 256) {
              resultToShow = '${resultToShow.substring(0, 256)}...';
            }
            _printColored('Tool.result', '${part.name}: $resultToShow', '\x1B[96m');
          }
        }
      case ChatMessageRole.model:
        final modelName = entry.modelName;
        for (final part in message.parts) {
          if (part is TextPart) {
            _printColored(modelName, part.text, '\x1B[93m');
          } else if (part is ToolPart && part.kind == ToolPartKind.call) {
            final args = const JsonEncoder.withIndent('  ').convert(
              part.arguments,
            );
            _printColored('Tool.call', '${part.name}($args)', '\x1B[95m');
          }
        }
      case ChatMessageRole.system:
        _printColored(role.name.toUpperCase(), message.text, '\x1B[91m');
    }
  }

  void _printColored(String label, String text, String color) {
    if (noColor) {
      print('$label: $text');
    } else {
      print('$color$label\x1B[0m: $text');
    }
  }

  void _handleClear() {
    onClearHistory();
    final agent = getAgent();
    print('History cleared. Chatting with ${agent.model}');
  }

  Future<void> _handleModel(List<String> args) async {
    final agent = getAgent();
    if (args.isEmpty) {
      print('Current agent: ${agent.model}');
    } else {
      final newAgentName = args.join(' ');
      final success = await onSetAgent(newAgentName);
      if (success) {
        print('Agent set to: ${getAgent().model}');
      }
    }
  }

  void _handleSystem(List<String> args) {
    if (args.isEmpty) {
      final systemPrompt = getSystemPrompt();
      if (systemPrompt == null || systemPrompt.isEmpty) {
        print('No system prompt configured.');
      } else {
        print('System prompt:');
        print(systemPrompt);
      }
    } else {
      final newPrompt = args.join(' ');
      onSetSystemPrompt(newPrompt);
      print('System prompt updated.');
    }
  }

  void _handleVerbose() {
    onToggleVerbose();
    final enabled = isVerbose();
    print('Verbose mode ${enabled ? 'enabled' : 'disabled'}.');
  }

  void _handleThinking() {
    onToggleThinking();
    final enabled = isThinkingEnabled();
    print('Thinking display ${enabled ? 'enabled' : 'disabled'}.');
  }

  void _printError(String message) {
    if (noColor) {
      stderr.writeln('Error: $message');
    } else {
      stderr.writeln('\x1B[91mError: $message\x1B[0m');
    }
  }
}
