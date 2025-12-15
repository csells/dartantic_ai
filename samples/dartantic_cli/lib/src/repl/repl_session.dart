// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cli_repl/cli_repl.dart';
import 'package:dartantic_ai/dartantic_ai.dart';

import '../mcp/mcp_tool_collector.dart';
import '../prompt/prompt_processor.dart';
import '../settings/settings.dart';
import 'history_entry.dart';
import 'repl_command_handler.dart';

/// Manages an interactive REPL session.
///
/// Handles the main loop, conversation history, MCP tools, and streaming
/// responses.
class ReplSession {
  /// Creates a REPL session.
  ReplSession({
    required this.settings,
    required String initialAgentName,
    required this.noColor,
    required this.workingDirectory,
    bool? verbose,
    bool? enableThinking,
  })  : _currentAgentName = initialAgentName,
        _verbose = verbose ?? false,
        _enableThinking = enableThinking;

  /// The loaded settings.
  final Settings settings;

  /// Whether color output is disabled.
  final bool noColor;

  /// Working directory for file operations.
  final String? workingDirectory;

  String _currentAgentName;
  Agent? _agent;
  final List<HistoryEntry> _history = [];
  final McpToolCollector _toolCollector = McpToolCollector();
  List<Tool> _tools = [];
  String? _systemPrompt;
  bool _verbose;
  bool? _enableThinking;

  /// The current agent instance.
  Agent get agent {
    _agent ??= _createAgent();
    return _agent!;
  }

  /// The current conversation history.
  List<HistoryEntry> get history => _history;

  /// The current list of MCP tools.
  List<Tool> get tools => _tools;

  /// The current system prompt.
  String? get systemPrompt => _systemPrompt;

  /// Whether verbose mode is enabled.
  bool get verbose => _verbose;

  /// Whether thinking display is enabled.
  bool get enableThinking => _enableThinking ?? false;

  /// Starts the REPL session.
  ///
  /// Returns the exit code.
  Future<int> run() async {
    // Initialize agent and tools
    await _initializeAgent();

    // Print welcome message
    _printWelcome();

    // Create command handler
    final commandHandler = ReplCommandHandler(
      help: _helpText,
      getAgent: () => agent,
      getHistory: () => _history,
      getTools: () => _tools,
      getSystemPrompt: () => _systemPrompt,
      onClearHistory: _clearHistory,
      onSetAgent: _setAgent,
      onSetSystemPrompt: _setSystemPrompt,
      onToggleVerbose: _toggleVerbose,
      onToggleThinking: _toggleThinking,
      isVerbose: () => _verbose,
      isThinkingEnabled: () => _enableThinking ?? false,
      noColor: noColor,
    );

    // Create REPL with blue prompt
    final promptColor = noColor ? '' : '\x1B[94m';
    final resetColor = noColor ? '' : '\x1B[0m';
    final repl = Repl(prompt: '${promptColor}You$resetColor: ');

    // Main REPL loop
    for (final line in repl.run()) {
      if (line.trim().isEmpty) continue;

      // Handle slash commands
      final result = await commandHandler.handleCommand(line: line.trim());
      if (result.shouldExit) break;
      if (result.commandHandled) continue;

      // Process user input and send to agent
      await _handleUserInput(line.trim());
    }

    // Cleanup
    _toolCollector.dispose();

    return 0;
  }

  Future<void> _initializeAgent() async {
    final agentSettings = settings.agents[_currentAgentName];

    // Collect MCP tools if configured
    if (agentSettings?.mcpServers.isNotEmpty ?? false) {
      _tools = await _toolCollector.collectTools(agentSettings!.mcpServers);
    }

    // Set up system prompt
    _systemPrompt = agentSettings?.system;

    // Determine thinking setting
    _enableThinking ??= agentSettings?.thinking ?? settings.thinking ?? false;

    // Add system message to history if present
    if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
      _history.add(
        HistoryEntry(
          message: ChatMessage.system(_systemPrompt!),
          modelName: '',
        ),
      );
    }

    // Create the agent
    _agent = _createAgent();
  }

  Agent _createAgent() {
    final agentSettings = settings.agents[_currentAgentName];
    final modelString = agentSettings?.model ?? _currentAgentName;

    return Agent(
      modelString,
      tools: _tools.isNotEmpty ? _tools : null,
      enableThinking: _enableThinking ?? false,
    );
  }

  Future<void> _handleUserInput(String input) async {
    // Process prompt for @file attachments
    final promptProcessor = PromptProcessor(workingDirectory: workingDirectory);
    final processed = await promptProcessor.process(input);

    if (!processed.isSuccess) {
      _printError('Error: ${processed.error}');
      return;
    }

    // Get messages for agent (excludes system which is in history)
    final messages = _history
        .where((e) => e.message.role != ChatMessageRole.system)
        .map((e) => e.message)
        .toList();

    // Print model name before response
    final modelColor = noColor ? '' : '\x1B[93m';
    final resetColor = noColor ? '' : '\x1B[0m';
    stdout.write('$modelColor${agent.model}$resetColor: ');
    await stdout.flush();

    // Track state for streaming output
    var inThinkingMode = false;
    LanguageModelUsage? lastUsage;

    // Collect messages for history
    final collectedMessages = <ChatMessage>[];

    // Stream the response
    await for (final chunk in agent.sendStream(
      processed.prompt,
      history: messages,
      attachments: processed.attachments,
    )) {
      // Handle thinking output
      if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
        if ((_enableThinking ?? false)) {
          if (!inThinkingMode) {
            inThinkingMode = true;
            if (noColor) {
              stdout.write('[Thinking]\n');
            } else {
              stdout.write('\x1b[2m[Thinking]\n');
            }
          }
          stdout.write(chunk.thinking);
        }
      }

      // Handle regular output
      if (chunk.output.isNotEmpty) {
        if (inThinkingMode) {
          inThinkingMode = false;
          if (noColor) {
            stdout.write('\n[/Thinking]\n\n');
          } else {
            stdout.write('\n[/Thinking]\x1b[0m\n\n');
          }
        }
        stdout.write(chunk.output);
      }

      // Track usage
      if (chunk.usage != null) {
        lastUsage = chunk.usage;
      }

      // Collect messages
      if (chunk.messages.isNotEmpty) {
        collectedMessages.addAll(chunk.messages);
      }

      await stdout.flush();
    }

    stdout.write('\n\n');
    await stdout.flush();

    // Add collected messages to history
    for (final msg in collectedMessages) {
      _history.add(
        HistoryEntry(
          message: msg,
          modelName: msg.role == ChatMessageRole.model ? agent.model : '',
        ),
      );
    }

    // Print usage if verbose
    if (_verbose && lastUsage != null) {
      _printUsage(lastUsage);
    }
  }

  void _printWelcome() {
    print(_helpText);
    print('');
    if (_tools.isNotEmpty) {
      print('Loaded ${_tools.length} MCP tools for agent "$_currentAgentName".');
    }
    print('');
  }

  String get _helpText => '''
dartantic repl - Interactive chat mode

Commands:
  /exit, /quit    Exit the REPL
  /help           Show this help message
  /model [name]   View or switch the current agent
  /models [filter] List available models
  /tools          Show available MCP tools
  /messages       Display conversation history
  /clear          Clear conversation history
  /system [text]  View or set system prompt
  /verbose        Toggle verbose output (token usage)
  /thinking       Toggle thinking output display

Use @filename to attach files to your message.
''';

  void _clearHistory() {
    _history.clear();
    // Re-add system prompt if present
    if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
      _history.add(
        HistoryEntry(
          message: ChatMessage.system(_systemPrompt!),
          modelName: '',
        ),
      );
    }
  }

  Future<bool> _setAgent(String agentName) async {
    try {
      // Dispose existing MCP clients
      _toolCollector.dispose();
      _tools = [];

      // Update agent name
      _currentAgentName = agentName;

      // Reinitialize
      final agentSettings = settings.agents[_currentAgentName];

      // Collect new MCP tools
      if (agentSettings?.mcpServers.isNotEmpty ?? false) {
        _tools = await _toolCollector.collectTools(agentSettings!.mcpServers);
      }

      // Update system prompt from new agent settings
      _systemPrompt = agentSettings?.system;

      // Update thinking from new agent settings
      _enableThinking = agentSettings?.thinking ?? settings.thinking ?? false;

      // Create new agent
      _agent = _createAgent();

      if (_tools.isNotEmpty) {
        print('Loaded ${_tools.length} MCP tools.');
      }

      return true;
    } on Exception catch (e) {
      _printError('Failed to set agent: $e');
      return false;
    }
  }

  void _setSystemPrompt(String prompt) {
    _systemPrompt = prompt;

    // Update history - remove old system message and add new one
    _history.removeWhere((e) => e.message.role == ChatMessageRole.system);
    _history.insert(
      0,
      HistoryEntry(
        message: ChatMessage.system(prompt),
        modelName: '',
      ),
    );
  }

  void _toggleVerbose() {
    _verbose = !_verbose;
  }

  void _toggleThinking() {
    _enableThinking = !(_enableThinking ?? false);
  }

  void _printUsage(LanguageModelUsage usage) {
    final usageInfo = StringBuffer();
    if (usage.promptTokens != null) {
      usageInfo.write('Input: ${usage.promptTokens} tokens');
    }
    if (usage.responseTokens != null) {
      if (usageInfo.isNotEmpty) usageInfo.write(', ');
      usageInfo.write('Output: ${usage.responseTokens} tokens');
    }
    if (usage.totalTokens != null) {
      if (usageInfo.isNotEmpty) usageInfo.write(', ');
      usageInfo.write('Total: ${usage.totalTokens} tokens');
    }

    if (usageInfo.isNotEmpty) {
      if (noColor) {
        stderr.writeln('Usage: $usageInfo');
      } else {
        stderr.writeln('\x1b[2mUsage: $usageInfo\x1b[0m');
      }
    }
  }

  void _printError(String message) {
    if (noColor) {
      stderr.writeln(message);
    } else {
      stderr.writeln('\x1B[91m$message\x1B[0m');
    }
  }
}
