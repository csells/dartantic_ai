import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart' show WhereNotNullExtension;

import '../helpers/message_part_helpers.dart';
import 'anthropic_chat.dart';

final Logger _logger = Logger('dartantic.chat.mappers.anthropic');

const _defaultMaxTokens = 1024;

/// Creates an Anthropic [a.CreateMessageRequest] from a list of messages and
/// options.
a.CreateMessageRequest createMessageRequest(
  List<ChatMessage> messages, {
  required String modelName,
  required AnthropicChatOptions? options,
  required AnthropicChatOptions defaultOptions,
  List<Tool>? tools,
  double? temperature,
  JsonSchema? outputSchema,
}) {
  // Handle tools
  final hasTools = tools != null && tools.isNotEmpty;

  final systemMsg = messages.firstOrNull?.role == ChatMessageRole.system
      ? (messages.firstOrNull!.parts.firstOrNull as TextPart?)?.text
      : null;

  final structuredTools = hasTools ? tools.toTool() : null;

  _logger.fine(
    'Creating Anthropic message request for ${messages.length} messages',
  );
  final messagesDtos = messages.toMessages();

  _logger.fine(
    'Tool configuration: hasTools=$hasTools, toolCount=${tools?.length ?? 0}',
  );

  return a.CreateMessageRequest(
    model: a.Model.modelId(modelName),
    messages: messagesDtos,
    maxTokens:
        options?.maxTokens ?? defaultOptions.maxTokens ?? _defaultMaxTokens,
    stopSequences: options?.stopSequences ?? defaultOptions.stopSequences,
    system: systemMsg != null
        ? a.CreateMessageRequestSystem.text(systemMsg)
        : null,
    temperature:
        temperature ?? options?.temperature ?? defaultOptions.temperature,
    topK: options?.topK ?? defaultOptions.topK,
    topP: options?.topP ?? defaultOptions.topP,
    metadata: a.CreateMessageRequestMetadata(
      userId: options?.userId ?? defaultOptions.userId,
    ),
    tools: structuredTools,
    toolChoice: hasTools
        ? const a.ToolChoice(type: a.ToolChoiceType.auto)
        : null,
    stream: true,
  );
}

/// Extension on [List<msg.Message>] to convert messages to Anthropic SDK
/// messages.
extension MessageListMapper on List<ChatMessage> {
  /// Converts this list of [ChatMessage]s to a list of Anthropic SDK
  /// [a.Message]s.
  List<a.Message> toMessages() {
    _logger.fine('Converting $length messages to Anthropic format');
    final result = <a.Message>[];
    final consecutiveToolMessages = <ChatMessage>[];

    void flushToolMessages() {
      if (consecutiveToolMessages.isNotEmpty) {
        _logger.fine(
          'Flushing ${consecutiveToolMessages.length} '
          'consecutive tool messages',
        );
        result.add(_mapToolMessages(consecutiveToolMessages));
        consecutiveToolMessages.clear();
      }
    }

    for (final message in this) {
      switch (message.role) {
        case ChatMessageRole.system:
          flushToolMessages();
          continue; // System message set in request params
        case ChatMessageRole.user:
          // Check if this is a tool result message
          if (message.parts.whereType<ToolPart>().isNotEmpty) {
            _logger.fine(
              'Adding user message with tool parts to consecutive tool '
              'messages',
            );
            consecutiveToolMessages.add(message);
          } else {
            flushToolMessages();
            final res = _mapUserMessage(message);
            result.add(res);
          }
        case ChatMessageRole.model:
          flushToolMessages();
          final res = _mapModelMessage(message);
          result.add(res);
      }
    }

    flushToolMessages(); // Flush any remaining tool messages
    return result;
  }

  a.Message _mapUserMessage(ChatMessage message) {
    final textParts = message.parts.whereType<TextPart>().toList();
    final dataParts = message.parts.whereType<DataPart>().toList();
    _logger.fine(
      'Mapping user message: ${textParts.length} text parts, '
      '${dataParts.length} data parts',
    );

    if (dataParts.isEmpty) {
      // Text-only message
      final text = message.parts.text;
      if (text.isEmpty) {
        throw ArgumentError(
          'User message cannot have empty content. '
          'Message parts: ${message.parts}',
        );
      }
      return a.Message(
        role: a.MessageRole.user,
        content: a.MessageContent.text(text),
      );
    } else {
      // Multimodal message
      final blocks = <a.Block>[];

      for (final part in message.parts) {
        if (part is TextPart) {
          blocks.add(a.Block.text(text: part.text));
        } else if (part is DataPart) {
          blocks.add(_mapDataPartToBlock(part));
        }
      }

      return a.Message(
        role: a.MessageRole.user,
        content: a.MessageContent.blocks(blocks),
      );
    }
  }

  a.Block _mapDataPartToBlock(DataPart dataPart) {
    if (dataPart.mimeType.startsWith('image/')) {
      // Images: Use native image blocks for better quality
      return a.Block.image(
        source: a.ImageBlockSource(
          type: a.ImageBlockSourceType.base64,
          mediaType: switch (dataPart.mimeType) {
            'image/jpeg' => a.ImageBlockSourceMediaType.imageJpeg,
            'image/png' => a.ImageBlockSourceMediaType.imagePng,
            'image/gif' => a.ImageBlockSourceMediaType.imageGif,
            'image/webp' => a.ImageBlockSourceMediaType.imageWebp,
            _ => throw AssertionError(
              'Unsupported image MIME type: ${dataPart.mimeType}',
            ),
          },
          data: base64Encode(dataPart.bytes),
        ),
      );
    } else {
      // Non-images: Use dartantic_ai format as text
      final base64Data = base64Encode(dataPart.bytes);
      return a.Block.text(
        text:
            '[media: ${dataPart.mimeType}] '
            'data:${dataPart.mimeType};base64,$base64Data',
      );
    }
  }

  a.Message _mapModelMessage(ChatMessage message) {
    final textParts = message.parts.whereType<TextPart>().toList();
    final toolParts = message.parts.whereType<ToolPart>().toList();
    _logger.fine(
      'Mapping model message: ${textParts.length} text parts, '
      '${toolParts.length} tool parts',
    );

    if (toolParts.isEmpty) {
      // Text-only response
      final text = message.parts.text;
      if (text.isEmpty && message.parts.isNotEmpty) {
        throw ArgumentError(
          'Assistant message has empty text content. '
          'Message parts: ${message.parts}',
        );
      }
      return a.Message(
        role: a.MessageRole.assistant,
        content: a.MessageContent.text(text),
      );
    } else {
      // Response with tool calls
      return a.Message(
        role: a.MessageRole.assistant,
        content: a.MessageContent.blocks(
          toolParts
              .map(
                (toolPart) => a.Block.toolUse(
                  id: toolPart.id,
                  name: toolPart.name,
                  input: toolPart.arguments ?? {},
                ),
              )
              .toList(growable: false),
        ),
      );
    }
  }

  a.Message _mapToolMessages(List<ChatMessage> messages) {
    _logger.fine(
      'Mapping ${messages.length} tool messages to Anthropic blocks',
    );
    final blocks = <a.Block>[];

    for (final message in messages) {
      for (final part in message.parts) {
        if (part is ToolPart && part.kind == ToolPartKind.result) {
          blocks.add(
            a.Block.toolResult(
              toolUseId: part.id,
              // ignore: avoid_dynamic_calls
              content: a.ToolResultBlockContent.text(
                ToolResultHelpers.serialize(part.result),
              ),
            ),
          );
        }
      }
    }

    return a.Message(
      role: a.MessageRole.user,
      content: a.MessageContent.blocks(blocks),
    );
  }
}

/// Extension on [a.Message] to convert an Anthropic SDK message to a
/// [ChatResult].
extension MessageMapper on a.Message {
  /// Converts this Anthropic SDK [a.Message] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult() {
    final parts = _mapMessageContent(content);
    final message = ChatMessage(role: ChatMessageRole.model, parts: parts);
    _logger.fine(
      'Converting Anthropic message to ChatResult with ${parts.length} parts',
    );

    return ChatResult<ChatMessage>(
      id: id,
      output: message,
      messages: [message],
      finishReason: _mapFinishReason(stopReason),
      metadata: {'model': model, 'stop_sequence': stopSequence},
      usage: _mapUsage(usage),
    );
  }
}

/// A [StreamTransformer] that converts a stream of Anthropic
/// [a.MessageStreamEvent]s into [ChatResult]s.
class MessageStreamEventTransformer
    extends
        StreamTransformerBase<a.MessageStreamEvent, ChatResult<ChatMessage>> {
  /// Creates a [MessageStreamEventTransformer].
  MessageStreamEventTransformer();

  /// The last message ID.
  String? lastMessageId;

  /// Map of content block index -> tool call ID.
  final Map<int, String> _toolCallIdByIndex = {};

  /// Map of content block index -> tool name.
  final Map<int, String> _toolNameByIndex = {};

  /// Accumulator for tool arguments during streaming (by content block index).
  final Map<int, StringBuffer> _toolArgumentsByIndex = {};

  /// Seed arguments captured from ToolUseBlock.start when provided fully.
  final Map<int, Map<String, dynamic>> _toolSeedArgsByIndex = {};

  /// Binds this transformer to a stream of [a.MessageStreamEvent]s, producing a
  /// stream of [ChatResult]s.
  @override
  Stream<ChatResult<ChatMessage>> bind(Stream<a.MessageStreamEvent> stream) =>
      stream
          .map(
            (event) => switch (event) {
              final a.MessageStartEvent e => _mapMessageStartEvent(e),
              final a.MessageDeltaEvent e => _mapMessageDeltaEvent(e),
              final a.ContentBlockStartEvent e => _mapContentBlockStartEvent(e),
              final a.ContentBlockDeltaEvent e => _mapContentBlockDeltaEvent(e),
              final a.ContentBlockStopEvent e => _mapContentBlockStopEvent(e),
              final a.MessageStopEvent e => _mapMessageStopEvent(e),
              a.PingEvent() => null,
              a.ErrorEvent() => null,
            },
          )
          .whereNotNull();

  ChatResult<ChatMessage> _mapMessageStartEvent(a.MessageStartEvent e) {
    final message = e.message;

    final msgId = message.id ?? lastMessageId ?? '';
    lastMessageId = msgId;
    final parts = _mapMessageContent(e.message.content);
    _logger.fine(
      'Processing message start event: messageId=$msgId, parts=${parts.length}',
    );

    return ChatResult<ChatMessage>(
      id: msgId,
      output: ChatMessage(role: ChatMessageRole.model, parts: parts),
      messages: [ChatMessage(role: ChatMessageRole.model, parts: parts)],
      finishReason: _mapFinishReason(e.message.stopReason),
      metadata: {
        if (e.message.model != null) 'model': e.message.model,
        if (e.message.stopSequence != null)
          'stop_sequence': e.message.stopSequence,
      },
      usage: _mapUsage(e.message.usage),
    );
  }

  ChatResult<ChatMessage> _mapMessageDeltaEvent(a.MessageDeltaEvent e) =>
      ChatResult<ChatMessage>(
        id: lastMessageId,
        output: const ChatMessage(role: ChatMessageRole.model, parts: []),
        messages: const [ChatMessage(role: ChatMessageRole.model, parts: [])],
        finishReason: _mapFinishReason(e.delta.stopReason),
        metadata: {
          if (e.delta.stopSequence != null)
            'stop_sequence': e.delta.stopSequence,
        },
        usage: _mapMessageDeltaUsage(e.usage),
      );

  ChatResult<ChatMessage> _mapContentBlockStartEvent(
    a.ContentBlockStartEvent e,
  ) {
    final parts = _mapContentBlock(e.contentBlock);
    _logger.fine(
      'Processing content block start event: index=${e.index}, '
      'parts=${parts.length}, contentBlock=$e.contentBlock',
    );

    // Track tool call IDs and names by content block index
    final cb = e.contentBlock;
    if (cb is a.ToolUseBlock) {
      _toolCallIdByIndex[e.index] = cb.id;
      _toolNameByIndex[e.index] = cb.name;

      // Capture any initial args if present (small payloads may arrive fully
      // in the start block without deltas)
      final input = cb.input;
      if (input.isNotEmpty) {
        _toolSeedArgsByIndex[e.index] = Map<String, dynamic>.from(input);
      }
    }

    return ChatResult<ChatMessage>(
      id: lastMessageId,
      output: ChatMessage(role: ChatMessageRole.model, parts: parts),
      messages: [ChatMessage(role: ChatMessageRole.model, parts: parts)],
      finishReason: FinishReason.unspecified,
      metadata: const {},
      usage: null,
    );
  }

  ChatResult<ChatMessage> _mapContentBlockDeltaEvent(
    a.ContentBlockDeltaEvent e,
  ) {
    // Handle InputJsonBlockDelta specially to accumulate arguments
    if (e.delta is a.InputJsonBlockDelta &&
        _toolCallIdByIndex.containsKey(e.index)) {
      final delta = e.delta as a.InputJsonBlockDelta;
      _toolArgumentsByIndex.putIfAbsent(e.index, StringBuffer.new);
      _toolArgumentsByIndex[e.index]!.write(delta.partialJson);

      // If we start receiving deltas, prefer them over any seeded args
      if (_toolSeedArgsByIndex.containsKey(e.index)) {
        _toolSeedArgsByIndex.remove(e.index);
      }

      // Return empty result for accumulation
      return ChatResult<ChatMessage>(
        id: lastMessageId,
        output: const ChatMessage(role: ChatMessageRole.model, parts: []),
        messages: const [],
        finishReason: FinishReason.unspecified,
        metadata: {'index': e.index},
        usage: null,
      );
    }

    final parts = _mapContentBlockDelta(_toolCallIdByIndex[e.index], e.delta);
    _logger.fine(
      'Processing content block delta event: index=${e.index}, '
      'parts=${parts.length}',
    );
    return ChatResult<ChatMessage>(
      id: lastMessageId,
      output: ChatMessage(role: ChatMessageRole.model, parts: parts),
      messages: [ChatMessage(role: ChatMessageRole.model, parts: parts)],
      finishReason: FinishReason.unspecified,
      metadata: {'index': e.index},
      usage: null,
    );
  }

  ChatResult<ChatMessage>? _mapContentBlockStopEvent(
    a.ContentBlockStopEvent e,
  ) {
    // If we have accumulated arguments for this tool, create a complete tool
    // part
    final toolId = _toolCallIdByIndex.remove(e.index);
    final toolName = _toolNameByIndex.remove(e.index);

    if (toolId != null) {
      final argsBuffer = _toolArgumentsByIndex.remove(e.index);
      final argsJson = argsBuffer?.toString() ?? '';
      final seededArgs = _toolSeedArgsByIndex.remove(e.index);

      // Return a result with the complete tool call
      return ChatResult<ChatMessage>(
        id: lastMessageId,
        output: ChatMessage(
          role: ChatMessageRole.model,
          parts: [
            ToolPart.call(
              id: toolId,
              name: toolName ?? '',
              arguments: argsJson.isNotEmpty
                  ? json.decode(argsJson)
                  : (seededArgs ?? <String, dynamic>{}),
            ),
          ],
        ),
        messages: const [],
        finishReason: FinishReason.unspecified,
        metadata: const {},
        usage: null,
      );
    }

    return null;
  }

  ChatResult<ChatMessage>? _mapMessageStopEvent(a.MessageStopEvent e) {
    // Clear any tracking state for safety
    lastMessageId = null;
    _toolCallIdByIndex.clear();
    _toolNameByIndex.clear();
    _toolArgumentsByIndex.clear();
    _toolSeedArgsByIndex.clear();
    return null;
  }
}

/// Maps an Anthropic [a.MessageContent] to message parts.
List<Part> _mapMessageContent(a.MessageContent content) => switch (content) {
  final a.MessageContentText t => [TextPart(t.value)],
  final a.MessageContentBlocks b => [
    // Extract text parts
    ...b.value.whereType<a.TextBlock>().map((t) => TextPart(t.text)),
    // Do not emit tool use parts here; they stream via block events.
  ],
};

/// Maps an Anthropic [a.Block] to message parts.
List<Part> _mapContentBlock(a.Block contentBlock) => switch (contentBlock) {
  final a.TextBlock t => [TextPart(t.text)],
  final a.ImageBlock i => [
    DataPart(
      Uint8List.fromList(i.source.data.codeUnits),
      mimeType: 'image/png',
    ),
  ],
  // Do not emit tool use blocks at start; emit at stop with full args.
  final a.ToolUseBlock _ => const [],
  final a.ToolResultBlock tr => [TextPart(tr.content.text)],
};

/// Maps an Anthropic [a.BlockDelta] to message parts.
List<Part> _mapContentBlockDelta(String? lastToolId, a.BlockDelta blockDelta) =>
    switch (blockDelta) {
      final a.TextBlockDelta t => [TextPart(t.text)],
      final a.InputJsonBlockDelta _ => const [],
    };

/// Extension on [List<Tool>] to convert tool specs to Anthropic SDK tools.
extension ToolSpecListMapper on List<Tool> {
  /// Converts this list of [Tool]s to a list of Anthropic SDK [a.Tool]s.
  List<a.Tool> toTool() {
    _logger.fine('Converting $length tools to Anthropic format');
    return map(_mapTool).toList(growable: false);
  }

  a.Tool _mapTool(Tool tool) => a.Tool.custom(
    name: tool.name,
    description: tool.description,
    inputSchema: Map<String, dynamic>.from(tool.inputSchema.schemaMap ?? {}),
  );
}

/// Maps an Anthropic [a.StopReason] to a [FinishReason].
FinishReason _mapFinishReason(a.StopReason? reason) => switch (reason) {
  a.StopReason.endTurn => FinishReason.stop,
  a.StopReason.maxTokens => FinishReason.length,
  a.StopReason.stopSequence => FinishReason.stop,
  a.StopReason.toolUse => FinishReason.toolCalls,
  null => FinishReason.unspecified,
};

/// Maps Anthropic [a.Usage] to [LanguageModelUsage].
LanguageModelUsage _mapUsage(a.Usage? usage) => LanguageModelUsage(
  promptTokens: usage?.inputTokens,
  responseTokens: usage?.outputTokens,
  totalTokens: usage?.inputTokens != null && usage?.outputTokens != null
      ? usage!.inputTokens + usage.outputTokens
      : null,
);

/// Maps Anthropic [a.MessageDeltaUsage] to [LanguageModelUsage].
LanguageModelUsage _mapMessageDeltaUsage(a.MessageDeltaUsage? usage) =>
    LanguageModelUsage(
      responseTokens: usage?.outputTokens,
      totalTokens: usage?.outputTokens,
    );
