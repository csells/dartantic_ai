import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'openai_responses_attachment_collector.dart';

/// Maps OpenAI Responses API items and content to dartantic Parts.
///
/// Handles conversion of response items (function calls, outputs, messages)
/// and output message content (text, refusals) into the dartantic Part
/// representation.
class OpenAIResponsesPartMapper {
  /// Creates a new part mapper.
  const OpenAIResponsesPartMapper();

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.part_mapper',
  );

  /// Maps response items to dartantic Parts.
  ///
  /// Returns a record containing the mapped parts and a mapping of tool call
  /// IDs to their names (needed for mapping function outputs).
  ({List<Part> parts, Map<String, String> toolCallNames}) mapResponseItems(
    List<openai.ResponseItem> items,
    AttachmentCollector attachments,
  ) {
    final parts = <Part>[];
    final toolCallNames = <String, String>{};

    _logger.info('Mapping ${items.length} response items');
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      _logger.info('Processing response item: ${item.runtimeType}');
      if (item is openai.OutputMessage) {
        final messageParts = mapOutputMessage(item.content, attachments);
        _logger.info(
          'OutputMessage has ${item.content.length} content items, '
          'mapped to ${messageParts.length} parts',
        );
        for (final part in messageParts) {
          if (part is TextPart) {
            _logger.info('Adding TextPart with text: "${part.text}"');
          }
        }
        parts.addAll(messageParts);
        continue;
      }

      if (item is openai.FunctionCall) {
        _logger.fine(
          'Adding function call to final result: ${item.name} '
          '(id=${item.callId})',
        );
        toolCallNames[item.callId] = item.name;
        parts.add(
          ToolPart.call(
            id: item.callId,
            name: item.name,
            arguments: decodeArguments(item.arguments),
          ),
        );
        continue;
      }

      if (item is openai.FunctionCallOutput) {
        final toolName = toolCallNames[item.callId] ?? item.callId;
        parts.add(
          ToolPart.result(
            id: item.callId,
            name: toolName,
            result: decodeResult(item.output),
          ),
        );
        continue;
      }

      if (item is openai.Reasoning) {
        // Already accumulated via ResponseReasoningSummaryTextDelta
        continue;
      }

      if (item is openai.CodeInterpreterCall) {
        // Extract file outputs from code interpreter results
        final containerId = item.containerId;
        if (containerId != null && item.results != null) {
          for (final result in item.results!) {
            if (result is openai.CodeInterpreterFiles) {
              for (final file in result.files) {
                final fileId = file.fileId ?? file.id;
                if (fileId != null) {
                  _logger.info(
                    'Found code interpreter file output: '
                    'container_id=$containerId, file_id=$fileId',
                  );
                  attachments.trackContainerCitation(
                    containerId: containerId,
                    fileId: fileId,
                  );
                }
              }
            }
          }
        }
        // Events also streamed in ChatResult.metadata
        continue;
      }

      if (item is openai.ImageGenerationCall) {
        attachments.registerImageCall(item, index);
        continue;
      }

      if (item is openai.WebSearchCall || item is openai.FileSearchCall) {
        // Events streamed in ChatResult.metadata
        continue;
      }

      if (item is openai.LocalShellCall ||
          item is openai.LocalShellCallOutput ||
          item is openai.ComputerCallOutput ||
          item is openai.McpCall ||
          item is openai.McpListTools ||
          item is openai.McpApprovalRequest ||
          item is openai.McpApprovalResponse) {
        // Events streamed in ChatResult.metadata
        continue;
      }
    }

    return (parts: parts, toolCallNames: toolCallNames);
  }

  /// Maps output message content to dartantic Parts.
  List<Part> mapOutputMessage(
    List<openai.ResponseContent> content,
    AttachmentCollector attachments,
  ) {
    final parts = <Part>[];
    for (final entry in content) {
      _logger.info('Processing ResponseContent: ${entry.runtimeType}');
      if (entry is openai.OutputTextContent) {
        _logger.info('OutputTextContent text: "${entry.text}"');
        parts.add(TextPart(entry.text));

        // Extract container file citations from annotations
        for (final annotation in entry.annotations) {
          if (annotation is openai.ContainerFileCitation) {
            _logger.info(
              'Found container file citation: '
              'container_id=${annotation.containerId}, '
              'file_id=${annotation.fileId}',
            );

            // Track files for downloading as DataParts
            attachments.trackContainerCitation(
              containerId: annotation.containerId,
              fileId: annotation.fileId,
            );
            _logger.info('Queued file for download: ${annotation.fileId}');
          }
        }
      } else if (entry is openai.RefusalContent) {
        parts.add(TextPart(entry.refusal));
      } else {
        final json = entry.toJson();
        _logger.info('OtherResponseContent: $json');
        // Check if this is reasoning content that shouldn't be in output
        if (json['type'] == 'reasoning_summary_text') {
          _logger.info(
            'Skipping reasoning_summary_text from output - '
            'already in thinking buffer',
          );
          // Skip - already accumulated via ResponseReasoningSummaryTextDelta
          continue;
        }
        parts.add(TextPart(jsonEncode(json)));
      }
    }
    return parts;
  }

  /// Decodes function call arguments from JSON string.
  Map<String, dynamic> decodeArguments(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'value': decoded};
  }

  /// Decodes function call result from JSON string.
  dynamic decodeResult(String raw) => jsonDecode(raw);
}
