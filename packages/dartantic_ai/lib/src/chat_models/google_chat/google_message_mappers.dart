import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;
import 'package:logging/logging.dart';

import '../helpers/google_schema_helpers.dart';
import '../helpers/message_part_helpers.dart';
import '../helpers/protobuf_value_helpers.dart';
import '../helpers/tool_id_helpers.dart';
import 'google_chat.dart'
    show
        ChatGoogleGenerativeAISafetySetting,
        ChatGoogleGenerativeAISafetySettingCategory,
        ChatGoogleGenerativeAISafetySettingThreshold;

/// Logger for Google message mapping operations.
final Logger _logger = Logger('dartantic.chat.mappers.google');

/// Extension on [List<ChatMessage>] to convert messages to Gemini content.
extension MessageListMapper on List<ChatMessage> {
  /// Converts this list of [ChatMessage]s to a list of [gl.Content]s.
  ///
  /// Groups consecutive tool result messages into a single `Content` so we can
  /// attach all [gl.FunctionResponse] parts in one payload.
  List<gl.Content> toContentList() {
    final nonSystemMessages = where(
      (message) => message.role != ChatMessageRole.system,
    ).toList();
    _logger.fine(
      'Converting ${nonSystemMessages.length} non-system messages to Google '
      'format',
    );

    final result = <gl.Content>[];

    for (var i = 0; i < nonSystemMessages.length; i++) {
      final message = nonSystemMessages[i];
      final hasToolResults = message.parts.whereType<ToolPart>().any(
        (p) => p.kind == ToolPartKind.result,
      );

      if (hasToolResults) {
        final toolMessages = <ChatMessage>[message];
        var j = i + 1;
        while (j < nonSystemMessages.length) {
          final next = nonSystemMessages[j];
          final nextHasToolResults = next.parts.whereType<ToolPart>().any(
            (p) => p.kind == ToolPartKind.result,
          );
          if (!nextHasToolResults) break;
          toolMessages.add(next);
          j++;
        }
        result.add(_mapToolResultMessages(toolMessages));
        i = j - 1;
      } else {
        result.add(_mapMessage(message));
      }
    }

    return result;
  }

  gl.Content _mapMessage(ChatMessage message) {
    switch (message.role) {
      case ChatMessageRole.system:
        throw AssertionError('System messages should already be filtered out');
      case ChatMessageRole.user:
        return _mapUserMessage(message);
      case ChatMessageRole.model:
        return _mapModelMessage(message);
    }
  }

  gl.Content _mapUserMessage(ChatMessage message) {
    _logger.fine('Mapping user message with ${message.parts.length} parts');
    return gl.Content(
      parts: _mapParts(
        message.parts,
        includeToolCalls: false,
        includeToolResults: true,
      ),
      role: 'user',
    );
  }

  gl.Content _mapModelMessage(ChatMessage message) {
    _logger.fine('Mapping model message with ${message.parts.length} parts');
    return gl.Content(
      parts: _mapParts(
        message.parts,
        includeToolCalls: true,
        includeToolResults: false,
      ),
      role: 'model',
    );
  }

  gl.Content _mapToolResultMessages(List<ChatMessage> messages) {
    final parts = <gl.Part>[];
    _logger.fine(
      'Creating function responses for ${messages.length} tool result '
      'messages',
    );

    for (final message in messages) {
      parts.addAll(
        _mapParts(
          message.parts,
          includeToolCalls: false,
          includeToolResults: true,
        ),
      );
    }

    return gl.Content(parts: parts, role: 'user');
  }

  List<gl.Part> _mapParts(
    Iterable<Part> parts, {
    required bool includeToolCalls,
    required bool includeToolResults,
  }) {
    final mappedParts = <gl.Part>[];

    for (final part in parts) {
      switch (part) {
        case TextPart(:final text):
          if (text.isNotEmpty) mappedParts.add(gl.Part(text: text));
        case DataPart(:final bytes, :final mimeType):
          mappedParts.add(
            gl.Part(
              inlineData: gl.Blob(mimeType: mimeType, data: bytes),
            ),
          );
        case LinkPart(:final url, :final mimeType):
          mappedParts.add(
            gl.Part(
              fileData: gl.FileData(
                fileUri: url.toString(),
                mimeType: mimeType ?? 'application/octet-stream',
              ),
            ),
          );
        case ToolPart(:final kind):
          if (includeToolCalls && kind == ToolPartKind.call) {
            mappedParts.add(_mapToolCallPart(part));
          } else if (includeToolResults && kind == ToolPartKind.result) {
            mappedParts.add(_mapToolResultPart(part));
          }
        default:
          break;
      }
    }

    return mappedParts;
  }

  gl.Part _mapToolCallPart(ToolPart part) {
    final arguments = part.arguments ?? const <String, dynamic>{};
    final callId = part.id.isNotEmpty
        ? part.id
        : ToolIdHelpers.generateToolCallId(
            toolName: part.name,
            providerHint: 'google',
            arguments: arguments,
          );

    return gl.Part(
      functionCall: gl.FunctionCall(
        id: callId,
        name: part.name,
        args: ProtobufValueHelpers.structFromJson(arguments),
      ),
    );
  }

  gl.Part _mapToolResultPart(ToolPart part) {
    final responseMap = ToolResultHelpers.ensureMap(part.result);
    _logger.fine('Creating function response for tool: ${part.name}');

    final responseId = part.id.isNotEmpty
        ? part.id
        : ToolIdHelpers.generateToolCallId(
            toolName: part.name,
            providerHint: 'google',
            arguments: responseMap,
          );

    return gl.Part(
      functionResponse: gl.FunctionResponse(
        id: responseId,
        name: part.name,
        response: ProtobufValueHelpers.structFromJson(responseMap),
      ),
    );
  }
}

/// Extension on [gl.GenerateContentResponse] to convert to [ChatResult].
extension GenerateContentResponseMapper on gl.GenerateContentResponse {
  /// Converts this [gl.GenerateContentResponse] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult(String model) {
    final candidateList = candidates;
    if (candidateList.isEmpty) {
      throw StateError('Google response did not contain any candidates.');
    }

    final candidate = candidateList.first;
    final parts = <Part>[];
    final executableCodeParts = <gl.ExecutableCode>[];
    final executionResults = <gl.CodeExecutionResult>[];
    final thinkingBuffer = StringBuffer();

    final contentParts = candidate.content?.parts ?? const <gl.Part>[];
    _logger.fine(
      'Processing ${contentParts.length} parts from Google response',
    );

    for (final part in contentParts) {
      // Check if this is a thinking part (thought=true)
      final isThought = part.thought;

      final text = part.text;
      if (text != null && text.isNotEmpty) {
        if (isThought) {
          // Accumulate thinking content, don't add to regular parts
          thinkingBuffer.write(text);
          _logger.fine('Accumulated thinking text: ${text.length} chars');
        } else {
          parts.add(TextPart(text));
        }
      }

      final blob = part.inlineData;
      final blobData = blob?.data;
      if (blob != null && blobData != null) {
        parts.add(DataPart(blobData, mimeType: blob.mimeType));
      }

      final fileData = part.fileData;
      if (fileData != null) {
        parts.add(
          LinkPart(Uri.parse(fileData.fileUri), mimeType: fileData.mimeType),
        );
      }

      final functionCall = part.functionCall;
      if (functionCall != null) {
        final args = ProtobufValueHelpers.structToJson(functionCall.args);
        final callId = (functionCall.id.isNotEmpty)
            ? functionCall.id
            : ToolIdHelpers.generateToolCallId(
                toolName: functionCall.name,
                providerHint: 'google',
                arguments: args,
              );
        parts.add(
          ToolPart.call(id: callId, name: functionCall.name, arguments: args),
        );
      }

      final functionResponse = part.functionResponse;
      if (functionResponse != null) {
        final responseMap = ProtobufValueHelpers.structToJson(
          functionResponse.response,
        );
        final responseId = (functionResponse.id.isNotEmpty)
            ? functionResponse.id
            : ToolIdHelpers.generateToolCallId(
                toolName: functionResponse.name,
                providerHint: 'google',
                arguments: responseMap,
              );
        parts.add(
          ToolPart.result(
            id: responseId,
            name: functionResponse.name,
            result: responseMap,
          ),
        );
      }

      final executableCode = part.executableCode;
      if (executableCode != null) {
        executableCodeParts.add(executableCode);
      }

      final executionResult = part.codeExecutionResult;
      if (executionResult != null) {
        executionResults.add(executionResult);
      }
    }

    final message = ChatMessage(role: ChatMessageRole.model, parts: parts);

    final metadata = <String, dynamic>{
      'model': model,
      'model_version': modelVersion,
    };

    final blockReason = promptFeedback?.blockReason.value;
    if (blockReason != null) {
      metadata['block_reason'] = blockReason;
    }

    final safetyRatings = candidate.safetyRatings
        .map(
          (rating) => {
            'category': rating.category.value,
            'probability': rating.probability.value,
          },
        )
        .toList(growable: false);
    if (safetyRatings.isNotEmpty) {
      metadata['safety_ratings'] = safetyRatings;
    }

    final citations = candidate.citationMetadata?.citationSources
        .map(
          (s) => {
            'start_index': s.startIndex,
            'end_index': s.endIndex,
            'uri': s.uri,
            'license': s.license,
          },
        )
        .toList(growable: false);
    if (citations != null && citations.isNotEmpty) {
      metadata['citation_metadata'] = citations;
    }

    if (executableCodeParts.isNotEmpty) {
      metadata['executable_code'] = executableCodeParts
          .map((code) => code.toJson())
          .toList(growable: false);
    }
    if (executionResults.isNotEmpty) {
      metadata['code_execution_result'] = executionResults
          .map((result) => result.toJson())
          .toList(growable: false);
    }

    metadata.removeWhere(
      (_, value) => value == null || (value is List && value.isEmpty),
    );

    // Add thinking as first-class field
    final thinking = thinkingBuffer.isNotEmpty
        ? thinkingBuffer.toString()
        : null;
    if (thinking != null) {
      _logger.fine('Added thinking: ${thinking.length} chars');
    }

    return ChatResult<ChatMessage>(
      output: message,
      messages: [message],
      thinking: thinking,
      finishReason: _mapFinishReason(candidate.finishReason),
      metadata: metadata,
      usage: usageMetadata != null
          ? LanguageModelUsage(
              promptTokens: usageMetadata?.promptTokenCount,
              responseTokens: usageMetadata?.candidatesTokenCount,
              totalTokens: usageMetadata?.totalTokenCount,
            )
          : null,
    );
  }

  FinishReason _mapFinishReason(gl.Candidate_FinishReason? reason) {
    switch (reason) {
      case gl.Candidate_FinishReason.stop:
        return FinishReason.stop;
      case gl.Candidate_FinishReason.maxTokens:
        return FinishReason.length;
      case gl.Candidate_FinishReason.safety ||
          gl.Candidate_FinishReason.blocklist ||
          gl.Candidate_FinishReason.prohibitedContent ||
          gl.Candidate_FinishReason.imageSafety ||
          gl.Candidate_FinishReason.spii:
        return FinishReason.contentFilter;
      case gl.Candidate_FinishReason.recitation:
        return FinishReason.recitation;
      case gl.Candidate_FinishReason.malformedFunctionCall:
        return FinishReason.unspecified;
      case gl.Candidate_FinishReason.language ||
          gl.Candidate_FinishReason.other ||
          gl.Candidate_FinishReason.finishReasonUnspecified ||
          null:
        return FinishReason.unspecified;
    }
    return FinishReason.unspecified;
  }
}

/// Extension on [List<ChatGoogleGenerativeAISafetySetting>] to convert to
/// Gemini safety settings.
extension SafetySettingsMapper on List<ChatGoogleGenerativeAISafetySetting> {
  /// Converts this list of safety settings to [gl.SafetySetting]s.
  List<gl.SafetySetting> toSafetySettings() {
    _logger.fine('Converting $length safety settings to Google format');
    return map(
      (setting) => gl.SafetySetting(
        category: switch (setting.category) {
          ChatGoogleGenerativeAISafetySettingCategory.unspecified =>
            gl.HarmCategory.harmCategoryUnspecified,
          ChatGoogleGenerativeAISafetySettingCategory.harassment =>
            gl.HarmCategory.harmCategoryHarassment,
          ChatGoogleGenerativeAISafetySettingCategory.hateSpeech =>
            gl.HarmCategory.harmCategoryHateSpeech,
          ChatGoogleGenerativeAISafetySettingCategory.sexuallyExplicit =>
            gl.HarmCategory.harmCategorySexuallyExplicit,
          ChatGoogleGenerativeAISafetySettingCategory.dangerousContent =>
            gl.HarmCategory.harmCategoryDangerousContent,
        },
        threshold: switch (setting.threshold) {
          ChatGoogleGenerativeAISafetySettingThreshold.unspecified =>
            gl.SafetySetting_HarmBlockThreshold.harmBlockThresholdUnspecified,
          ChatGoogleGenerativeAISafetySettingThreshold.blockLowAndAbove =>
            gl.SafetySetting_HarmBlockThreshold.blockLowAndAbove,
          ChatGoogleGenerativeAISafetySettingThreshold.blockMediumAndAbove =>
            gl.SafetySetting_HarmBlockThreshold.blockMediumAndAbove,
          ChatGoogleGenerativeAISafetySettingThreshold.blockOnlyHigh =>
            gl.SafetySetting_HarmBlockThreshold.blockOnlyHigh,
          ChatGoogleGenerativeAISafetySettingThreshold.blockNone =>
            gl.SafetySetting_HarmBlockThreshold.blockNone,
        },
      ),
    ).toList(growable: false);
  }
}

/// Extension on [List<Tool>?] to convert to Gemini tools.
extension ChatToolListMapper on List<Tool>? {
  /// Converts this list of [Tool]s to a list of [gl.Tool]s, optionally enabling
  /// code execution and Google Search.
  List<gl.Tool>? toToolList({
    required bool enableCodeExecution,
    required bool enableGoogleSearch,
  }) {
    final hasTools = this != null && this!.isNotEmpty;
    _logger.fine(
      'Converting tools to Google format: hasTools=$hasTools, '
      'enableCodeExecution=$enableCodeExecution, '
      'enableGoogleSearch=$enableGoogleSearch, '
      'toolCount=${this?.length ?? 0}',
    );

    final functionDeclarations = hasTools
        ? this!
              .map(
                (tool) => gl.FunctionDeclaration(
                  name: tool.name,
                  description: tool.description,
                  parameters: tool.inputSchema.schemaMap != null
                      ? GoogleSchemaHelpers.schemaFromJson(
                          Map<String, dynamic>.from(
                            tool.inputSchema.schemaMap!,
                          ),
                        )
                      : null,
                ),
              )
              .toList(growable: false)
        : null;

    final codeExecution = enableCodeExecution ? gl.CodeExecution() : null;
    final googleSearch = enableGoogleSearch ? gl.Tool_GoogleSearch() : null;

    if ((functionDeclarations == null || functionDeclarations.isEmpty) &&
        codeExecution == null &&
        googleSearch == null) {
      return null;
    }

    return [
      gl.Tool(
        functionDeclarations: functionDeclarations ?? const [],
        codeExecution: codeExecution,
        googleSearch: googleSearch,
      ),
    ];
  }
}

/// Extension on [Map<String, dynamic>] to convert to a Gemini [gl.Schema].
extension GoogleSchemaMapper on Map<String, dynamic> {
  /// Converts this map to a [gl.Schema].
  gl.Schema toGoogleSchema() =>
      GoogleSchemaHelpers.schemaFromJson(Map<String, dynamic>.from(this));
}
