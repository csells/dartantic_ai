import 'dart:async';
import 'dart:convert';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;
// ignore: implementation_imports
import 'package:anthropic_sdk_dart/src/generated/client.dart' as ag;
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import 'anthropic_chat_options.dart';
import 'anthropic_message_mappers.dart';

/// Wrapper around [Anthropic Messages
/// API](https://docs.anthropic.com/en/api/messages) (aka Claude API).
class AnthropicChatModel extends ChatModel<AnthropicChatOptions> {
  /// Creates a [AnthropicChatModel] instance.
  AnthropicChatModel({
    required super.name,
    required String apiKey,
    Uri? baseUrl,
    super.tools,
    super.temperature,
    bool enableThinking = false,
    http.Client? client,
    AnthropicChatOptions? defaultOptions,
  }) : _enableThinking = enableThinking,
       _client = _AnthropicStreamingClient(
         apiKey: apiKey,
         baseUrl: baseUrl?.toString(),
         client: client,
       ),
       super(defaultOptions: defaultOptions ?? const AnthropicChatOptions()) {
    _logger.info(
      'Creating Anthropic model: $name with '
      '${tools?.length ?? 0} tools, temp: $temperature, '
      'thinking: $enableThinking',
    );
  }

  /// Logger for Anthropic chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.anthropic');

  final _AnthropicStreamingClient _client;
  final bool _enableThinking;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    AnthropicChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    _logger.info(
      'Starting Anthropic chat stream with '
      '${messages.length} messages for model: $name',
    );

    final transformer = MessageStreamEventTransformer();
    final request = createMessageRequest(
      messages,
      modelName: name,
      enableThinking: _enableThinking,
      tools: tools,
      temperature: temperature,
      options: options,
      defaultOptions: defaultOptions,
      outputSchema: outputSchema,
    );

    var chunkCount = 0;
    // TODO(https://github.com/davidmigloz/langchain_dart/issues/811): revert to
    // `_client.createMessageStream(...).transform(transformer)` once
    // `anthropic_sdk_dart` understands the `signature_delta` union variant.
    await for (final result in _createMessageEventStream(
      request,
      transformer,
    ).transform(transformer)) {
      chunkCount++;
      _logger.fine('Received Anthropic stream chunk $chunkCount');
      // Filter system messages from the response
      yield ChatResult<ChatMessage>(
        id: result.id,
        output: result.output,
        messages: result.messages,
        finishReason: result.finishReason,
        metadata: result.metadata,
        thinking: result.thinking,
        usage: result.usage,
      );
    }
  }

  @override
  void dispose() => _client.endSession();

  Stream<a.MessageStreamEvent> _createMessageEventStream(
    a.CreateMessageRequest request,
    MessageStreamEventTransformer transformer,
  ) async* {
    final lines = _client.rawMessageStream(request.copyWith(stream: true));

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;

      final map = json.decode(payload) as Map<String, dynamic>;
      final type = map['type'];

      if (type == 'signature_delta' ||
          (map['delta'] is Map &&
              (map['delta'] as Map)['type'] == 'signature_delta')) {
        final signature =
            map['signature'] as String? ??
            (map['delta'] as Map?)?['signature'] as String?;
        if (signature != null && signature.isNotEmpty) {
          _logger.fine('Captured signature delta for thinking block');
          transformer.recordSignatureDelta(signature);
        } else {
          _logger.warning(
            'Received signature_delta event without signature: $map',
          );
        }
        continue;
      }

      yield a.MessageStreamEvent.fromJson(map);
    }
  }
}

class _AnthropicStreamingClient extends a.AnthropicClient {
  _AnthropicStreamingClient({
    required super.apiKey,
    super.baseUrl,
    super.client,
  });

  Stream<String> rawMessageStream(a.CreateMessageRequest request) async* {
    final response = await makeRequestStream(
      baseUrl: 'https://api.anthropic.com/v1',
      path: '/messages',
      method: ag.HttpMethod.post,
      requestType: 'application/json',
      responseType: 'application/json',
      body: request,
      headerParams: {if (apiKey.isNotEmpty) 'x-api-key': apiKey},
    );

    yield* response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
  }
}
