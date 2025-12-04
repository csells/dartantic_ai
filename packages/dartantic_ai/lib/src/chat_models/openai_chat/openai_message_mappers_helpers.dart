import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:openai_dart/openai_dart.dart';

import '../../shared/openai_utils.dart';
import 'openai_chat_options.dart';
import 'openai_message_mappers.dart';

/// Maps OpenAI finish reason to our FinishReason enum
FinishReason mapFinishReason(ChatCompletionFinishReason? reason) {
  if (reason == null) return FinishReason.unspecified;

  return switch (reason) {
    ChatCompletionFinishReason.stop => FinishReason.stop,
    ChatCompletionFinishReason.length => FinishReason.length,
    ChatCompletionFinishReason.toolCalls => FinishReason.toolCalls,
    ChatCompletionFinishReason.contentFilter => FinishReason.contentFilter,
    ChatCompletionFinishReason.functionCall => FinishReason.toolCalls,
  };
}

/// Maps OpenAI usage to our LanguageModelUsage
LanguageModelUsage mapUsage(CompletionUsage? usage) {
  if (usage == null) return const LanguageModelUsage();

  return LanguageModelUsage(
    promptTokens: usage.promptTokens,
    responseTokens: usage.completionTokens,
    totalTokens: usage.totalTokens,
  );
}

/// Creates OpenAI ResponseFormat from JsonSchema
ResponseFormat? _createResponseFormat(
  JsonSchema? outputSchema, {
  bool strictSchema = true,
}) {
  if (outputSchema == null) return null;

  return ResponseFormat.jsonSchema(
    jsonSchema: JsonSchemaObject(
      name: 'output_schema',
      description: 'Generated response following the provided schema',
      schema: OpenAIUtils.prepareSchemaForOpenAI(
        Map<String, dynamic>.from(outputSchema.schemaMap ?? {}),
        strict: strictSchema,
      ),
      strict: strictSchema,
    ),
  );
}

/// Creates a ChatCompletionRequest from the given input
CreateChatCompletionRequest createChatCompletionRequest(
  List<ChatMessage> messages, {
  required String modelName,
  required OpenAIChatOptions defaultOptions,
  List<Tool>? tools,
  double? temperature,
  OpenAIChatOptions? options,
  JsonSchema? outputSchema,
  bool strictSchema = true,
}) => CreateChatCompletionRequest(
  model: ChatCompletionModel.modelId(modelName),
  messages: messages.toOpenAIMessages(),
  tools: tools
      ?.map(
        (tool) => ChatCompletionTool(
          type: ChatCompletionToolType.function,
          function: FunctionObject(
            name: tool.name,
            description: tool.description,
            parameters: tool.inputSchema.schemaMap as Map<String, dynamic>?,
            strict: null, // Explicitly pass null to override any defaults
          ),
        ),
      )
      .toList(),
  toolChoice: null,
  responseFormat:
      _createResponseFormat(outputSchema, strictSchema: strictSchema) ??
      options?.responseFormat ??
      defaultOptions.responseFormat,
  maxTokens: options?.maxTokens ?? defaultOptions.maxTokens,
  n: options?.n ?? defaultOptions.n,
  temperature:
      temperature ?? options?.temperature ?? defaultOptions.temperature,
  topP: options?.topP ?? defaultOptions.topP,
  stop: (options?.stop ?? defaultOptions.stop) != null
      ? ChatCompletionStop.listString(options?.stop ?? defaultOptions.stop!)
      : null,
  stream: true,
  streamOptions: options?.streamOptions ?? defaultOptions.streamOptions,
  user: options?.user ?? defaultOptions.user,
  frequencyPenalty:
      options?.frequencyPenalty ?? defaultOptions.frequencyPenalty,
  logitBias: options?.logitBias ?? defaultOptions.logitBias,
  logprobs: options?.logprobs ?? defaultOptions.logprobs,
  presencePenalty: options?.presencePenalty ?? defaultOptions.presencePenalty,
  seed: options?.seed ?? defaultOptions.seed,
  topLogprobs: options?.topLogprobs ?? defaultOptions.topLogprobs,
);

/// Helper class to track streaming tool call state
class StreamingToolCall {
  /// Creates a new streaming tool call.
  StreamingToolCall({
    required this.id,
    required this.name,
    this.argumentsJson = '',
  });

  /// The ID of the tool call.
  String id;

  /// The name of the tool.
  String name;

  /// The arguments of the tool call.
  String argumentsJson;
}
