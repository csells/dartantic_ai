import 'package:dartantic_ai/dartantic_ai.dart';

import '../settings/settings.dart';

/// Collects tools from MCP servers defined in settings.
///
/// Creates MCP clients for each server configuration and retrieves
/// their available tools.
class McpToolCollector {
  final List<McpClient> _clients = [];

  /// Collects tools from all configured MCP servers.
  ///
  /// For each [McpServerSettings], creates the appropriate client
  /// (remote or local) and retrieves its tools.
  Future<List<Tool>> collectTools(List<McpServerSettings> servers) async {
    final tools = <Tool>[];

    for (final server in servers) {
      final client = _createClient(server);
      _clients.add(client);
      tools.addAll(await client.listTools());
    }

    return tools;
  }

  /// Creates an MCP client from server settings.
  McpClient _createClient(McpServerSettings server) {
    if (server.url != null) {
      // Remote HTTP server
      return McpClient.remote(
        server.name,
        url: Uri.parse(server.url!),
        headers: server.headers.isNotEmpty ? server.headers : null,
      );
    } else if (server.command != null) {
      // Local stdio server
      return McpClient.local(
        server.name,
        command: server.command!,
        args: server.args,
        environment: server.environment.isNotEmpty ? server.environment : null,
        workingDirectory: server.workingDirectory,
      );
    } else {
      throw ArgumentError(
        'MCP server "${server.name}" must have either url or command',
      );
    }
  }

  /// Disposes all MCP clients.
  void dispose() {
    for (final client in _clients) {
      client.dispose();
    }
    _clients.clear();
  }
}
