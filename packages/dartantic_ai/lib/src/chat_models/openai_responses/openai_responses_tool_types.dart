/// Constants for OpenAI Responses server-side tool types.
class OpenAIResponsesToolTypes {
  OpenAIResponsesToolTypes._();

  /// Web search tool type identifier.
  static const String webSearch = 'web_search';

  /// File search tool type identifier.
  static const String fileSearch = 'file_search';

  /// Image generation tool type identifier.
  static const String imageGeneration = 'image_generation';

  /// Local shell tool type identifier.
  static const String localShell = 'local_shell';

  /// MCP (Model Context Protocol) tool type identifier.
  static const String mcp = 'mcp';

  /// Code interpreter tool type identifier.
  static const String codeInterpreter = 'code_interpreter';
}
