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
    required this.pendingItems,
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

  /// Any pending items recovered from the stored session metadata.
  final List<openai.ResponseItem> pendingItems;

  /// Whether there is any concrete input to send to the API.
  bool get hasInput => input != null;
}

/// Converts between dartantic chat messages and OpenAI Responses API payloads.
class OpenAIResponsesMessageMapper {
  OpenAIResponsesMessageMapper._();

  /// Logger for message mapping operations.
  static final Logger log = Logger('dartantic.chat.mappers.openai_responses');

  /// Maps the provided [messages] into an [OpenAIResponsesHistorySegment]
  /// understood by the Responses API.
  static OpenAIResponsesHistorySegment mapHistory(
    List<ChatMessage> messages, {
    bool store = true,
    openai.ImageDetail imageDetail = openai.ImageDetail.auto,
  }) {
    log.fine('mapHistory called with ${messages.length} messages');
    for (var i = 0; i < messages.length; i++) {
      final parts = messages[i].parts.map((p) => p.runtimeType).join(', ');
      log.fine('  [$i]: ${messages[i].role.name} ($parts)');
    }

    if (messages.isEmpty) {
      return const OpenAIResponsesHistorySegment(
        items: [],
        input: null,
        instructions: null,
        previousResponseId: null,
        anchorIndex: -1,
        pendingItems: [],
      );
    }

    var startIndex = 0;
    String? instructions;
    final first = messages.first;
    if (first.role == ChatMessageRole.system) {
      instructions = first.text.trim().isEmpty ? null : first.text;
      startIndex = 1;
    }

    final session = store
        ? _findLatestSession(messages, from: startIndex)
        : null;

    // Get the response ID from the most recent message's session metadata.
    // This becomes the "previous" response ID for the current request.
    final previousResponseId = store
        ? OpenAIResponsesMetadata.responseId(session?.data)
        : null;

    final pendingItems = store
        ? OpenAIResponsesMetadata.pendingItems(session?.data)
        : const <openai.ResponseItem>[];

    final items = <openai.ResponseItem>[...pendingItems];

    var firstMessageIndex = session == null ? startIndex : session.index + 1;
    if (firstMessageIndex < startIndex) firstMessageIndex = startIndex;
    if (firstMessageIndex > messages.length) {
      firstMessageIndex = messages.length;
    }

    log.fine(
      'Mapping history: total=${messages.length}, startIndex=$startIndex, '
      'anchorIndex=${session?.index}, firstMessageIndex=$firstMessageIndex, '
      'pending=${pendingItems.length}, hasPrevId=${previousResponseId != null}',
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
      if (message.role == ChatMessageRole.system) {
        // System messages must only appear at index 0; skip any stray ones.
        continue;
      }
      items.addAll(_mapMessageParts(message, imageDetail: imageDetail));
    }

    final input = items.isEmpty
        ? null
        : openai.ResponseInputItems(List.of(items));

    // Only send instructions when starting a new session.
    final resolvedInstructions = previousResponseId == null
        ? instructions
        : null;

    return OpenAIResponsesHistorySegment(
      items: items,
      input: input,
      instructions: resolvedInstructions,
      previousResponseId: previousResponseId,
      anchorIndex: session?.index ?? -1,
      pendingItems: pendingItems,
    );
  }

  /// Validates that new messages being added to an existing session are valid.
  /// This is more lenient than _validateHistory since we're continuing a
  /// session.
  static void _validateNewMessages(List<ChatMessage> newMessages) {
    // New messages in a session continuation should generally just be
    // user or model messages, no system messages
    for (final message in newMessages) {
      if (message.role == ChatMessageRole.system) {
        throw ArgumentError(
          'System messages cannot be added mid-conversation in a session',
        );
      }
    }
    // We don't enforce strict alternation here because the orchestrator
    // may add multiple messages in sequence during tool execution
  }

  /// Ensures the conversation follows `system? -> user/model alternating`.
  static void _validateHistory(List<ChatMessage> messages) {
    if (messages.isEmpty) return;

    var index = 0;

    if (messages.first.role == ChatMessageRole.system) {
      index = 1;
      for (var i = index; i < messages.length; i++) {
        if (messages[i].role == ChatMessageRole.system) {
          throw ArgumentError(
            'Multiple system messages detected. Only index 0 may be system.',
          );
        }
      }
    }

    if (index < messages.length &&
        messages[index].role != ChatMessageRole.user) {
      throw ArgumentError(
        'First non-system message must be from user. '
        'Found ${messages[index].role.name} at index $index.',
      );
    }

    var expectingUser = true;
    for (var i = index; i < messages.length; i++) {
      final expected = expectingUser
          ? ChatMessageRole.user
          : ChatMessageRole.model;
      final actual = messages[i].role;
      if (actual != expected) {
        throw ArgumentError(
          'Conversation must alternate user/model. '
          'Expected ${expected.name} at index $i, found ${actual.name}.',
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
    final role = isUserMessage ? 'user' : 'assistant';

    void flushContent() {
      if (content.isEmpty) return;
      if (isUserMessage) {
        items.add(openai.InputMessage(role: role, content: List.of(content)));
      } else {
        // Model messages need to use OutputMessage
        items.add(
          openai.OutputMessage(
            role: role,
            content: List.of(content),
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            status: 'completed',
          ),
        );
      }
      content.clear();
    }

    for (final part in message.parts) {
      switch (part) {
        case TextPart(:final text):
          if (text.isNotEmpty) {
            if (isUserMessage) {
              content.add(openai.InputTextContent(text: text));
            } else {
              // Model messages use OutputTextContent
              content.add(
                openai.OutputTextContent(
                  text: text,
                  annotations: const [],
                ),
              );
            }
          }
        case DataPart(:final bytes, :final mimeType, :final name):
          if (mimeType.toLowerCase().startsWith('image/')) {
            final base64Data = base64Encode(bytes);
            content.add(
              openai.InputImageContent(
                detail: imageDetail,
                imageUrl: 'data:$mimeType;base64,$base64Data',
              ),
            );
          } else {
            final base64Data = base64Encode(bytes);
            final filename = name ?? Part.nameFromMimeType(mimeType);
            content.add(
              openai.InputFileContent(fileData: base64Data, filename: filename),
            );
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
            if (isUserMessage) {
              content.add(openai.InputTextContent(text: url.toString()));
            } else {
              content.add(
                openai.OutputTextContent(
                  text: url.toString(),
                  annotations: const [],
                ),
              );
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
    try {
      return jsonEncode(result);
    } on Object catch (_) {
      return result.toString();
    }
  }
}

class _SessionMetadata {
  const _SessionMetadata({required this.index, this.data});

  final int index;
  final Map<String, Object?>? data;
}
