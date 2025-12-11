/// Constants describing Anthropic Claude server-side tool identifiers.
class AnthropicServerToolTypes {
  AnthropicServerToolTypes._();

  /// Primary code execution sandbox tool.
  static const String codeExecution = 'code_execution';

  /// Text editor backing tool used during code execution sessions.
  static const String textEditorCodeExecution = 'text_editor_code_execution';

  /// Bash execution helper used within the code execution sandbox.
  static const String bashCodeExecution = 'bash_code_execution';

  /// Server-side web search tool.
  static const String webSearch = 'web_search';

  /// Server-side web fetch tool.
  static const String webFetch = 'web_fetch';

  /// Server-side tool use block type (before normalization).
  static const String serverToolUse = 'server_tool_use';

  /// Standard tool use block type.
  static const String toolUse = 'tool_use';

  /// Standard tool result block type.
  static const String toolResult = 'tool_result';

  /// Suffix indicating a tool result block type.
  static const String toolResultSuffix = '_tool_result';
}
