import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import 'cactus_chat_options.dart';

/// Chat API that enables to interact
/// with the LLMs in a chat-like fashion.
class CactusChatModel extends ChatModel<CactusChatOptions> {
  /// Creates a [CactusChatModel] instance.
  CactusChatModel({
    required this.sendChatStream,
    required super.name,
    super.temperature,
    CactusChatOptions? defaultOptions,
  }) : super(
         defaultOptions: defaultOptions ?? const CactusChatOptions(),
         /// tools isn't used in the CactusChatModel.
         /// Tools are added to Cactus Agents directly.
         tools: [],
       );

  static final Logger _logger = Logger('dartantic.chat.models.cactus');

  /// Function to stream chat with LLM
  Stream<ChatResult<ChatMessage>> Function(
    List<ChatMessage> messages, {
    CactusChatOptions? options,
    JsonSchema? outputSchema,
  })
  sendChatStream;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    CactusChatOptions? options,
    JsonSchema? outputSchema,
  }) {
    _logger.info(
      'Starting Cactus chat stream with ${messages.length} '
      'messages for model: $name',
    );

    return sendChatStream(
      messages,
      options: options,
      outputSchema: outputSchema,
    );
  }

  @override
  void dispose() {}
}
