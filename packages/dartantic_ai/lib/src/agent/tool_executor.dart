import 'dart:async';
import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

/// Result of executing a single tool
class ToolExecutionResult {
  /// Creates a new ToolExecutionResult
  const ToolExecutionResult({
    required this.toolPart,
    required this.resultPart,
    this.error,
    this.stackTrace,
  });

  /// The original tool call part
  final ToolPart toolPart;

  /// The result part containing the execution result
  final ToolPart resultPart;

  /// Error if the execution failed
  final Exception? error;

  /// Stack trace if the execution failed
  final StackTrace? stackTrace;

  /// Whether the execution succeeded
  bool get isSuccess => error == null;
}

/// Tool executor that handles standard tool execution.
///
/// This implementation:
/// - Executes tools sequentially
/// - Formats results as JSON strings
/// - Includes error details in results for LLM consumption
class ToolExecutor {
  /// Creates a new ToolExecutor
  const ToolExecutor();

  static final _logger = Logger('dartantic.executor.tool');

  /// Provider hint for debugging and logging.
  String get providerHint => 'default';

  /// Executes a list of tool calls and returns their results.
  ///
  /// This method handles:
  /// - Invoking the actual tool functions
  /// - Formatting results appropriately
  /// - Error handling and reporting
  ///
  /// Returns a list of ToolExecutionResult objects containing both successes
  /// and failures.
  Future<List<ToolExecutionResult>> executeBatch(
    List<ToolPart> toolCalls,
    Map<String, Tool> toolMap,
  ) async {
    final results = <ToolExecutionResult>[];

    // Execute tools sequentially
    for (final toolCall in toolCalls) {
      final result = await executeSingle(toolCall, toolMap);
      results.add(result);
    }

    return results;
  }

  /// Executes a single tool call.
  Future<ToolExecutionResult> executeSingle(
    ToolPart toolCall,
    Map<String, Tool> toolMap,
  ) async {
    final tool = toolMap[toolCall.name];

    if (tool == null) {
      _logger.warning(
        'Tool ${toolCall.name} not found in available tools: '
        '${toolMap.keys.join(', ')}',
      );

      final error = Exception('Tool ${toolCall.name} not found');
      return ToolExecutionResult(
        toolPart: toolCall,
        resultPart: ToolPart.result(
          id: toolCall.id,
          name: toolCall.name,
          result: formatError(error),
        ),
        error: error,
      );
    }

    _logger.fine(
      'Executing tool: ${toolCall.name} with args: '
      '${json.encode(toolCall.arguments ?? {})}',
    );

    try {
      final args = toolCall.arguments ?? {};
      final result = await tool.call(args);
      final resultString = formatResult(result);

      _logger.info(
        'Tool ${toolCall.name}(${toolCall.id}) executed '
        'successfully, result length: ${resultString.length}',
      );

      return ToolExecutionResult(
        toolPart: toolCall,
        resultPart: ToolPart.result(
          id: toolCall.id,
          name: toolCall.name,
          result: resultString,
        ),
      );
    } on Exception catch (error, stackTrace) {
      // Must catch this exception to pass the error along to the LLM
      _logger.warning(
        'Tool ${toolCall.name} execution failed: $error',
        error,
        stackTrace,
      );

      return ToolExecutionResult(
        toolPart: toolCall,
        resultPart: ToolPart.result(
          id: toolCall.id,
          name: toolCall.name,
          result: formatError(error),
        ),
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Formats a tool result for inclusion in the conversation.
  String formatResult(dynamic result) {
    if (result is String) {
      return result;
    }
    return json.encode(result);
  }

  /// Formats an error for inclusion in the conversation.
  String formatError(Exception error) =>
      json.encode({'error': error.toString()});
}
