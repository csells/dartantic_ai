import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../shared/openai_responses_metadata.dart';

/// Represents the mapped segment of history sent to the Responses API.
class OpenAIResponsesHistorySegment {
  /// Creates a new mapped history segment.
  const OpenAIResponsesHistorySegment({
    required this.items,
    required this.input,
    required this.instructions,
    required this.previousResponseId,
    required this.anchorIndex,
  });

  /// Concrete [openai.ResponseItem] payloads that will be sent to the API.
  final List<openai.ResponseItem> items;

  /// Serialized input payload or `null` when no new data must be sent.
  final openai.Input? input;

  /// Optional system instructions to provide to the API.
  final String? instructions;

  /// Response ID to resume from when using session persistence.
  final String? previousResponseId;

  /// Index of the conversation message that supplied session metadata.
  final int anchorIndex;

  /// Whether there is any concrete input to send to the API.
  bool get hasInput => input != null;
}

/// Converts between dartantic chat messages and OpenAI Responses API payloads.
class OpenAIResponsesMessageMapper {
  OpenAIResponsesMessageMapper._();

  /// Logger for message mapping operations.
  static final Logger log = Logger('dartantic.chat.mappers.openai_responses');

  /// Prefix for synthetic message IDs generated when converting model messages.
  static const _syntheticMessageIdPrefix = 'msg_';

  /// Maps the provided [messages] into an [OpenAIResponsesHistorySegment]
  /// understood by the Responses API.
  static OpenAIResponsesHistorySegment mapHistory(
    List<ChatMessage> messages, {
    bool store = true,
    openai.ImageDetail imageDetail = openai.ImageDetail.auto,
  }) {
    log.info('━━━ OpenAI Responses Message Mapping ━━━');
    log.info('Total messages in history: ${messages.length}');
    log.info('Store enabled: $store');

    for (var i = 0; i < messages.length; i++) {
      final parts = messages[i].parts.map((p) => p.runtimeType).join(', ');
      final metadata = messages[i].metadata;
      final hasSession = metadata.containsKey(
        OpenAIResponsesMetadata.sessionKey,
      );
      final responseIdInfo = OpenAIResponsesMetadata.responseId(
        OpenAIResponsesMetadata.getSessionData(metadata),
      );
      final sessionInfo = hasSession ? ' [HAS SESSION: $responseIdInfo]' : '';
      log.info('  [$i]: ${messages[i].role.name} ($parts)$sessionInfo');
    }

    if (messages.isEmpty) {
      log.info('No messages to map - returning empty segment');
      return const OpenAIResponsesHistorySegment(
        items: [],
        input: null,
        instructions: null,
        previousResponseId: null,
        anchorIndex: -1,
      );
    }

    const startIndex = 0;

    final session = store
        ? _findLatestSession(messages, from: startIndex)
        : null;

    // Get the response ID from the most recent message's session metadata.
    // This becomes the "previous" response ID for the current request.
    final previousResponseId = store
        ? OpenAIResponsesMetadata.responseId(session?.data)
        : null;

    // No pending items in dartantic - tools are executed synchronously
    final items = <openai.ResponseItem>[];

    var firstMessageIndex = session == null ? startIndex : session.index + 1;
    if (firstMessageIndex < startIndex) firstMessageIndex = startIndex;
    if (firstMessageIndex > messages.length) {
      firstMessageIndex = messages.length;
    }

    if (previousResponseId != null) {
      log.info('✓ Found previous session at index ${session?.index}');
      log.info('  Previous response ID: $previousResponseId');
      log.info(
        '  Will send messages from index $firstMessageIndex '
        'to ${messages.length - 1}',
      );
      log.info(
        '  → Sending only ${messages.length - firstMessageIndex} '
        'NEW messages (not ${messages.length} total)',
      );
    } else {
      log.info(
        '✗ No previous session found - '
        'sending all $firstMessageIndex messages',
      );
    }

    log.fine(
      'Mapping history: total=${messages.length}, startIndex=$startIndex, '
      'anchorIndex=${session?.index}, firstMessageIndex=$firstMessageIndex, '
      'hasPrevId=${previousResponseId != null}',
    );

    // When using session continuation, we only send new messages
    // So we should only validate the new portion of the conversation
    if (previousResponseId != null) {
      // With a session, validate only the new messages being added
      final newMessages = messages.sublist(firstMessageIndex);
      _validateNewMessages(newMessages);
    } else {
      // Without a session, validate the full conversation structure
      _validateHistory(messages);
    }

    for (var i = firstMessageIndex; i < messages.length; i++) {
      final message = messages[i];
      items.addAll(_mapMessageParts(message, imageDetail: imageDetail));
    }

    final input = items.isEmpty
        ? null
        : openai.ResponseInputItems(List.of(items));

    log.info('━━━ Mapping Complete ━━━');
    log.info('Actual items to send: ${items.length}');
    log.info('Using previousResponseId: ${previousResponseId ?? "none"}');
    log.info('');

    return OpenAIResponsesHistorySegment(
      items: items,
      input: input,
      instructions: null,
      previousResponseId: previousResponseId,
      anchorIndex: session?.index ?? -1,
    );
  }

  /// Validates that new messages being added to an existing session are valid.
  /// This is more lenient than _validateHistory since we're continuing a
  /// session.
  static void _validateNewMessages(List<ChatMessage> newMessages) {
    // Allow any message types when continuing a session
    // System messages are now supported mid-conversation
    // We don't enforce strict alternation here because the orchestrator
    // may add multiple messages in sequence during tool execution
  }

  /// Ensures the conversation follows reasonable structure.
  static void _validateHistory(List<ChatMessage> messages) {
    if (messages.isEmpty) return;

    // Find the first non-system message
    var firstNonSystemIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].role != ChatMessageRole.system) {
        firstNonSystemIndex = i;
        break;
      }
    }

    // If there are non-system messages, the first one should be from user
    if (firstNonSystemIndex >= 0 &&
        messages[firstNonSystemIndex].role != ChatMessageRole.user) {
      throw ArgumentError(
        'First non-system message must be from user. '
        'Found ${messages[firstNonSystemIndex].role.name} '
        'at index $firstNonSystemIndex.',
      );
    }

    // Check for reasonable alternation between user and model messages
    // (system messages can appear anywhere)
    var expectingUser = true;
    for (var i = firstNonSystemIndex; i < messages.length; i++) {
      final message = messages[i];
      if (message.role == ChatMessageRole.system) {
        // System messages don't affect alternation
        continue;
      }

      final expected = expectingUser
          ? ChatMessageRole.user
          : ChatMessageRole.model;
      if (message.role != expected) {
        throw ArgumentError(
          'Conversation must alternate user/model '
          '(system messages allowed anywhere). '
          'Expected ${expected.name} at index $i, found ${message.role.name}.',
        );
      }
      expectingUser = !expectingUser;
    }
  }

  static _SessionMetadata? _findLatestSession(
    List<ChatMessage> messages, {
    required int from,
  }) {
    for (var i = messages.length - 1; i >= from; i--) {
      final session = OpenAIResponsesMetadata.getSessionData(
        messages[i].metadata,
      );
      if (session != null) {
        return _SessionMetadata(index: i, data: session);
      }
    }
    return null;
  }

  static List<openai.ResponseItem> _mapMessageParts(
    ChatMessage message, {
    required openai.ImageDetail imageDetail,
  }) {
    final items = <openai.ResponseItem>[];
    final content = <openai.ResponseContent>[];
    final isUserMessage = message.role == ChatMessageRole.user;
    final isSystemMessage = message.role == ChatMessageRole.system;
    final isModelMessage = message.role == ChatMessageRole.model;

    // Determine the role string for the API
    final role = isSystemMessage
        ? 'system'
        : isUserMessage
        ? 'user'
        : 'assistant';

    void flushContent() {
      if (content.isEmpty) return;
      if (isModelMessage) {
        // Model messages need to use OutputMessage
        items.add(
          openai.OutputMessage(
            role: role,
            content: List.of(content),
            id:
                '$_syntheticMessageIdPrefix'
                '${DateTime.now().millisecondsSinceEpoch}',
            status: 'completed',
          ),
        );
      } else {
        // User and system messages use InputMessage
        items.add(openai.InputMessage(role: role, content: List.of(content)));
      }
      content.clear();
    }

    for (final part in message.parts) {
      switch (part) {
        case TextPart(:final text):
          if (text.isNotEmpty) {
            if (isModelMessage) {
              // Model messages use OutputTextContent
              content.add(
                openai.OutputTextContent(text: text, annotations: const []),
              );
            } else {
              // User and system messages use InputTextContent
              content.add(openai.InputTextContent(text: text));
            }
          }
        case DataPart(:final bytes, :final mimeType, :final name):
          if (mimeType.toLowerCase().startsWith('image/')) {
            // Images: Use InputImageContent
            final base64Data = base64Encode(bytes);
            content.add(
              openai.InputImageContent(
                detail: imageDetail,
                imageUrl: 'data:$mimeType;base64,$base64Data',
              ),
            );
          } else if (mimeType == 'application/pdf') {
            // PDFs: Use InputFileContent
            // (only file type supported by Responses API)
            final base64Data = base64Encode(bytes);
            final fileName = name ?? Part.nameFromMimeType(mimeType);
            final fileDataUrl = 'data:$mimeType;base64,$base64Data';
            content.add(
              openai.InputFileContent(
                filename: fileName,
                fileData: fileDataUrl,
              ),
            );
          } else {
            // All other files: Include as text with base64 data URL
            final base64Data = base64Encode(bytes);
            final fileDataUrl = 'data:$mimeType;base64,$base64Data';

            // Build prefix with optional filename
            final prefix = name != null
                ? '[file: $name, media: $mimeType]'
                : '[media: $mimeType]';
            final fileContent = '$prefix $fileDataUrl';

            if (isModelMessage) {
              content.add(
                openai.OutputTextContent(
                  text: fileContent,
                  annotations: const [],
                ),
              );
            } else {
              content.add(openai.InputTextContent(text: fileContent));
            }
          }
        case LinkPart(:final url, :final mimeType):
          final resolvedMime = mimeType ?? '';
          if (resolvedMime.toLowerCase().startsWith('image/')) {
            content.add(
              openai.InputImageContent(
                detail: imageDetail,
                imageUrl: url.toString(),
              ),
            );
          } else {
            if (isModelMessage) {
              content.add(
                openai.OutputTextContent(
                  text: url.toString(),
                  annotations: const [],
                ),
              );
            } else {
              content.add(openai.InputTextContent(text: url.toString()));
            }
          }
        case ToolPart(:final kind):
          flushContent();
          switch (kind) {
            case ToolPartKind.call:
              items.add(
                openai.FunctionCall(
                  arguments: jsonEncode(part.arguments ?? const {}),
                  callId: part.id,
                  name: part.name,
                ),
              );
            case ToolPartKind.result:
              items.add(
                openai.FunctionCallOutput(
                  callId: part.id,
                  output: _stringifyToolResult(part.result),
                ),
              );
          }
      }
    }

    flushContent();

    return items;
  }

  static String _stringifyToolResult(dynamic result) {
    if (result == null) return 'null';
    if (result is String) return result;
    return jsonEncode(result);
  }
}

class _SessionMetadata {
  const _SessionMetadata({required this.index, this.data});

  final int index;
  final Map<String, Object?>? data;
}
