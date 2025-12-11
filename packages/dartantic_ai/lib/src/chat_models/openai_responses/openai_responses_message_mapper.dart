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

    final sessionResolution = _resolveSession(
      messages: messages,
      store: store,
      startIndex: startIndex,
    );

    // No pending items in dartantic - tools are executed synchronously
    final items = <openai.ResponseItem>[];

    for (
      var i = sessionResolution.firstMessageIndex;
      i < messages.length;
      i++
    ) {
      final message = messages[i];
      items.addAll(_mapMessageParts(message, imageDetail: imageDetail));
    }

    final input = items.isEmpty
        ? null
        : openai.ResponseInputItems(List.of(items));

    log.info('━━━ Mapping Complete ━━━');
    log.info('Actual items to send: ${items.length}');
    final prevId = sessionResolution.previousResponseId ?? 'none';
    log.info('Using previousResponseId: $prevId');
    log.info('');

    return OpenAIResponsesHistorySegment(
      items: items,
      input: input,
      instructions: null,
      previousResponseId: sessionResolution.previousResponseId,
      anchorIndex: sessionResolution.anchorIndex,
    );
  }

  /// Resolves session metadata from message history.
  static _SessionResolution _resolveSession({
    required List<ChatMessage> messages,
    required bool store,
    required int startIndex,
  }) {
    final session = store
        ? _findLatestSession(messages, from: startIndex)
        : null;

    // Get the response ID from the most recent message's session metadata.
    // This becomes the "previous" response ID for the current request.
    final previousResponseId = store
        ? OpenAIResponsesMetadata.responseId(session?.data)
        : null;

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

    return _SessionResolution(
      previousResponseId: previousResponseId,
      anchorIndex: session?.index ?? -1,
      firstMessageIndex: firstMessageIndex,
    );
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
        case TextPart():
          _mapTextPart(part, content, isModelMessage);
        case DataPart():
          _mapDataPart(part, content, isModelMessage, imageDetail);
        case LinkPart():
          _mapLinkPart(part, content, isModelMessage, imageDetail);
        case ToolPart():
          flushContent();
          items.addAll(_mapToolPart(part));
      }
    }

    flushContent();

    return items;
  }

  /// Maps a TextPart to response content.
  static void _mapTextPart(
    TextPart part,
    List<openai.ResponseContent> content,
    bool isModelMessage,
  ) {
    if (part.text.isEmpty) return;
    if (isModelMessage) {
      // Model messages use OutputTextContent
      content.add(
        openai.OutputTextContent(text: part.text, annotations: const []),
      );
    } else {
      // User and system messages use InputTextContent
      content.add(openai.InputTextContent(text: part.text));
    }
  }

  /// Maps a DataPart to response content.
  static void _mapDataPart(
    DataPart part,
    List<openai.ResponseContent> content,
    bool isModelMessage,
    openai.ImageDetail imageDetail,
  ) {
    final mimeType = part.mimeType;
    final bytes = part.bytes;
    final name = part.name;

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
      // PDFs: Use InputFileContent (only file type supported by Responses API)
      final base64Data = base64Encode(bytes);
      final fileName = name ?? Part.nameFromMimeType(mimeType);
      final fileDataUrl = 'data:$mimeType;base64,$base64Data';
      content.add(
        openai.InputFileContent(filename: fileName, fileData: fileDataUrl),
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
          openai.OutputTextContent(text: fileContent, annotations: const []),
        );
      } else {
        content.add(openai.InputTextContent(text: fileContent));
      }
    }
  }

  /// Maps a LinkPart to response content.
  static void _mapLinkPart(
    LinkPart part,
    List<openai.ResponseContent> content,
    bool isModelMessage,
    openai.ImageDetail imageDetail,
  ) {
    final resolvedMime = part.mimeType ?? '';
    if (resolvedMime.toLowerCase().startsWith('image/')) {
      content.add(
        openai.InputImageContent(
          detail: imageDetail,
          imageUrl: part.url.toString(),
        ),
      );
    } else {
      if (isModelMessage) {
        content.add(
          openai.OutputTextContent(
            text: part.url.toString(),
            annotations: const [],
          ),
        );
      } else {
        content.add(openai.InputTextContent(text: part.url.toString()));
      }
    }
  }

  /// Maps a ToolPart to response items.
  static List<openai.ResponseItem> _mapToolPart(ToolPart part) {
    switch (part.kind) {
      case ToolPartKind.call:
        return [
          openai.FunctionCall(
            arguments: jsonEncode(part.arguments ?? const {}),
            callId: part.id,
            name: part.name,
          ),
        ];
      case ToolPartKind.result:
        return [
          openai.FunctionCallOutput(
            callId: part.id,
            output: _stringifyToolResult(part.result),
          ),
        ];
    }
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

/// Result of session resolution containing indices and session ID.
class _SessionResolution {
  const _SessionResolution({
    required this.previousResponseId,
    required this.anchorIndex,
    required this.firstMessageIndex,
  });

  /// Previous response ID to continue from.
  final String? previousResponseId;

  /// Index of the message containing session metadata.
  final int anchorIndex;

  /// Index of first message to send in this request.
  final int firstMessageIndex;
}
