import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;
import 'package:google_cloud_protobuf/protobuf.dart' as pb;
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../../custom_http_client.dart';
import '../../providers/google_api_utils.dart';
import '../../retry_http_client.dart';
import '../helpers/protobuf_value_helpers.dart';
import 'google_chat_options.dart';
import 'google_message_mappers.dart';
import 'google_server_side_tools.dart';

/// Wrapper around [Google AI for Developers](https://ai.google.dev/) API
/// (aka Gemini API).
class GoogleChatModel extends ChatModel<GoogleChatModelOptions> {
  /// Creates a [GoogleChatModel] instance.
  GoogleChatModel({
    required super.name,
    required String apiKey,
    required Uri baseUrl,
    http.Client? client,
    Map<String, String>? headers,
    super.tools,
    super.temperature,
    bool enableThinking = false,
    super.defaultOptions = const GoogleChatModelOptions(),
  }) : _enableThinking = enableThinking,
       _httpClient = CustomHttpClient(
         baseHttpClient: client ?? RetryHttpClient(inner: http.Client()),
         baseUrl: baseUrl,
         headers: {'x-goog-api-key': apiKey, ...?headers},
         queryParams: const {},
       ) {
    _logger.info(
      'Creating Google model: $name '
      'with ${super.tools?.length ?? 0} tools, temp: $temperature, '
      'thinking: $enableThinking',
    );
    _service = gl.GenerativeService(client: _httpClient);
  }

  /// Logger for Google chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.google');

  late final gl.GenerativeService _service;
  final CustomHttpClient _httpClient;
  final bool _enableThinking;

  /// The resolved base URL.
  @visibleForTesting
  Uri get resolvedBaseUrl => _httpClient.baseUrl;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    GoogleChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    final request = _buildRequest(
      messages,
      options: options,
      outputSchema: outputSchema,
    );

    var chunkCount = 0;
    _logger.info(
      'Starting Google chat stream with ${messages.length} messages '
      'for model: ${request.model}',
    );

    return _service.streamGenerateContent(request).map((response) {
      chunkCount++;
      _logger.fine('Received Google stream chunk $chunkCount');
      return response.toChatResult(request.model);
    });
  }

  gl.GenerateContentRequest _buildRequest(
    List<ChatMessage> messages, {
    GoogleChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    final normalizedModel = normalizeGoogleModelName(name);
    final safetySettings =
        (options?.safetySettings ?? defaultOptions.safetySettings)
            ?.toSafetySettings();

    final serverSideTools =
        options?.serverSideTools ?? defaultOptions.serverSideTools ?? const {};

    final enableCodeExecution = serverSideTools.contains(
      GoogleServerSideTool.codeExecution,
    );

    final generationConfig = _buildGenerationConfig(
      options: options,
      outputSchema: outputSchema,
    );

    final contents = messages.toContentList();

    // Gemini API requires at least one non-empty content item
    if (contents.isEmpty || contents.every((c) => c.parts.isEmpty)) {
      throw ArgumentError(
        'Cannot generate content with empty input. '
        'At least one message with non-empty content is required.',
      );
    }

    // Google doesn't support tools + outputSchema simultaneously.
    // When outputSchema is provided, exclude tools (double agent phase 2).
    final toolsToSend = outputSchema != null
        ? const <Tool>[]
        : (tools ?? const <Tool>[]);

    final toolConfig = _buildToolConfig(options);

    return gl.GenerateContentRequest(
      model: normalizedModel,
      systemInstruction: _extractSystemInstruction(messages),
      contents: contents,
      safetySettings: safetySettings ?? const [],
      generationConfig: generationConfig,
      toolConfig: toolConfig,
      tools:
          toolsToSend.toToolList(
            enableCodeExecution: enableCodeExecution,
            enableGoogleSearch: serverSideTools.contains(
              GoogleServerSideTool.googleSearch,
            ),
          ) ??
          const [],
    );
  }

  gl.ToolConfig? _buildToolConfig(GoogleChatModelOptions? options) {
    final mode =
        options?.functionCallingMode ?? defaultOptions.functionCallingMode;
    final allowedNames =
        options?.allowedFunctionNames ?? defaultOptions.allowedFunctionNames;

    // If no mode specified and no allowed names, use default behavior
    if (mode == null && allowedNames == null) return null;

    final glMode = switch (mode) {
      GoogleFunctionCallingMode.auto => gl.FunctionCallingConfig_Mode.auto,
      GoogleFunctionCallingMode.any => gl.FunctionCallingConfig_Mode.any,
      GoogleFunctionCallingMode.none => gl.FunctionCallingConfig_Mode.none,
      GoogleFunctionCallingMode.validated =>
        gl.FunctionCallingConfig_Mode.validated,
      null => gl.FunctionCallingConfig_Mode.auto, // default
    };

    return gl.ToolConfig(
      functionCallingConfig: gl.FunctionCallingConfig(
        mode: glMode,
        allowedFunctionNames: allowedNames ?? const [],
      ),
    );
  }

  gl.GenerationConfig _buildGenerationConfig({
    GoogleChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    final stopSequences =
        options?.stopSequences ??
        defaultOptions.stopSequences ??
        const <String>[];

    final responseMimeType = outputSchema != null
        ? 'application/json'
        : options?.responseMimeType ?? defaultOptions.responseMimeType;

    // Use native JSON Schema support via responseJsonSchema
    final responseJsonSchema = _resolveResponseJsonSchema(
      outputSchema: outputSchema,
      responseSchema: options?.responseSchema ?? defaultOptions.responseSchema,
    );

    final thinkingConfig = _buildThinkingConfig(options);

    return gl.GenerationConfig(
      candidateCount: options?.candidateCount ?? defaultOptions.candidateCount,
      stopSequences: stopSequences,
      maxOutputTokens:
          options?.maxOutputTokens ?? defaultOptions.maxOutputTokens,
      temperature:
          temperature ?? options?.temperature ?? defaultOptions.temperature,
      topP: options?.topP ?? defaultOptions.topP,
      topK: options?.topK ?? defaultOptions.topK,
      responseMimeType: responseMimeType ?? '',
      responseJsonSchema: responseJsonSchema,
      thinkingConfig: thinkingConfig,
    );
  }

  gl.ThinkingConfig? _buildThinkingConfig(GoogleChatModelOptions? options) {
    if (!_enableThinking) return null;

    // Default to dynamic thinking (-1) if no budget specified
    final thinkingBudget =
        options?.thinkingBudgetTokens ??
        defaultOptions.thinkingBudgetTokens ??
        -1;

    return gl.ThinkingConfig(
      includeThoughts: true,
      thinkingBudget: thinkingBudget,
    );
  }

  /// Converts JSON Schema to protobuf Value for native Gemini JSON Schema
  /// support. This uses the new responseJsonSchema API which accepts standard
  /// JSON Schema directly, eliminating the need for custom schema conversion.
  pb.Value? _resolveResponseJsonSchema({
    JsonSchema? outputSchema,
    Map<String, dynamic>? responseSchema,
  }) {
    if (outputSchema != null) {
      final schemaMap = Map<String, dynamic>.from(outputSchema.schemaMap ?? {});
      return ProtobufValueHelpers.valueFromJson(schemaMap);
    }
    if (responseSchema != null) {
      return ProtobufValueHelpers.valueFromJson(
        Map<String, dynamic>.from(responseSchema),
      );
    }
    return null;
  }

  gl.Content? _extractSystemInstruction(List<ChatMessage> messages) {
    for (final message in messages) {
      if (message.role == ChatMessageRole.system) {
        final instructions = message.parts
            .whereType<TextPart>()
            .map((part) => part.text)
            .where((text) => text.isNotEmpty)
            .join('\n')
            .trim();
        if (instructions.isEmpty) {
          return null;
        }
        return gl.Content(parts: [gl.Part(text: instructions)]);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _service.close();
  }
}
