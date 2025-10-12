import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_cloud_ai_generativelanguage_v1/generativelanguage.dart'
    as gl;
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../agent/tool_constants.dart';
import '../../custom_http_client.dart';
import '../../providers/google_provider.dart';
import '../../retry_http_client.dart';
import '../helpers/google_schema_helpers.dart';
import 'google_chat_options.dart';
import 'google_message_mappers.dart';

/// Wrapper around [Google AI for Developers](https://ai.google.dev/) API
/// (aka Gemini API).
class GoogleChatModel extends ChatModel<GoogleChatModelOptions> {
  /// Creates a [GoogleChatModel] instance.
  GoogleChatModel({
    required super.name,
    required String apiKey,
    Uri? baseUrl,
    http.Client? client,
    List<Tool>? tools,
    super.temperature,
    super.defaultOptions = const GoogleChatModelOptions(),
  }) : _httpClient = CustomHttpClient(
         baseHttpClient: client ?? RetryHttpClient(inner: http.Client()),
         baseUrl: baseUrl ?? GoogleProvider.defaultBaseUrl,
         headers: {'x-goog-api-key': apiKey},
         queryParams: const {},
       ),
       super(
         // Filter out return_result tool as Google has native typed output
         // support via responseMimeType: 'application/json'
         tools: tools?.where((t) => t.name != kReturnResultToolName).toList(),
       ) {
    _logger.info(
      'Creating Google model: $name '
      'with ${super.tools?.length ?? 0} tools, temp: $temperature',
    );
    _service = gl.GenerativeService(client: _httpClient);
  }

  /// Logger for Google chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.google');

  late final gl.GenerativeService _service;
  final CustomHttpClient _httpClient;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    GoogleChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    if (outputSchema != null && (tools?.isNotEmpty ?? false)) {
      throw ArgumentError(
        'Google Gemini does not support using tools and typed output '
        '(outputSchema) simultaneously. Either use tools without outputSchema, '
        'or use outputSchema without tools.',
      );
    }

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
    final normalizedModel = _normalizeModelName(name);
    final safetySettings =
        (options?.safetySettings ?? defaultOptions.safetySettings)
            ?.toSafetySettings();

    final enableCodeExecution =
        options?.enableCodeExecution ??
        defaultOptions.enableCodeExecution ??
        false;

    final generationConfig = _buildGenerationConfig(
      options: options,
      outputSchema: outputSchema,
    );

    return gl.GenerateContentRequest(
      model: normalizedModel,
      systemInstruction: _extractSystemInstruction(messages),
      contents: messages.toContentList(),
      safetySettings: safetySettings,
      generationConfig: generationConfig,
      tools: (tools ?? const []).toToolList(
        enableCodeExecution: enableCodeExecution,
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

    final responseSchema = _resolveResponseSchema(
      outputSchema: outputSchema,
      responseSchema: options?.responseSchema ?? defaultOptions.responseSchema,
    );

    return gl.GenerationConfig(
      candidateCount: options?.candidateCount ?? defaultOptions.candidateCount,
      stopSequences: stopSequences.isEmpty ? null : stopSequences,
      maxOutputTokens:
          options?.maxOutputTokens ?? defaultOptions.maxOutputTokens,
      temperature:
          temperature ?? options?.temperature ?? defaultOptions.temperature,
      topP: options?.topP ?? defaultOptions.topP,
      topK: options?.topK ?? defaultOptions.topK,
      responseMimeType: responseMimeType,
      responseSchema: responseSchema,
    );
  }

  gl.Schema? _resolveResponseSchema({
    JsonSchema? outputSchema,
    Map<String, dynamic>? responseSchema,
  }) {
    if (outputSchema != null) {
      final schemaMap = Map<String, dynamic>.from(outputSchema.schemaMap ?? {});
      return GoogleSchemaHelpers.schemaFromJson(schemaMap);
    }
    if (responseSchema != null) {
      return GoogleSchemaHelpers.schemaFromJson(
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

  String _normalizeModelName(String model) =>
      model.contains('/') ? model : 'models/$model';

  @override
  void dispose() {
    _service.close();
  }
}
