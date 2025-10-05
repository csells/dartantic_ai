import 'package:dartantic_interface/dartantic_interface.dart';

/// Builds ChatResult messages for OpenAI Responses streaming.
///
/// Separates message building logic from event handling to maintain
/// single responsibility principle.
class OpenAIResponsesMessageBuilder {
  /// Creates a new message builder.
  const OpenAIResponsesMessageBuilder();

  /// Creates a ChatResult with common structure.
  ChatResult<ChatMessage> createResult({
    required String responseId,
    required ChatMessage output,
    required List<ChatMessage> messages,
    required LanguageModelUsage usage,
    required FinishReason finishReason,
    required Map<String, Object?> resultMetadata,
  }) => ChatResult<ChatMessage>(
    id: responseId,
    output: output,
    messages: messages,
    usage: usage,
    finishReason: finishReason,
    metadata: resultMetadata,
  );

  /// Creates a ChatResult for streaming scenarios where text was streamed.
  ChatResult<ChatMessage> createStreamingResult({
    required String responseId,
    required List<Part> parts,
    required Map<String, Object?> messageMetadata,
    required LanguageModelUsage usage,
    required FinishReason finishReason,
    required Map<String, Object?> resultMetadata,
  }) {
    final nonTextParts = parts
        .where((p) => p is! TextPart)
        .toList(growable: false);

    final metadataOnlyOutput = ChatMessage(
      role: ChatMessageRole.model,
      parts: const [],
      metadata: messageMetadata,
    );

    final messages = nonTextParts.isNotEmpty
        ? [
            ChatMessage(
              role: ChatMessageRole.model,
              parts: nonTextParts,
              metadata: messageMetadata,
            ),
          ]
        : const <ChatMessage>[];

    return createResult(
      responseId: responseId,
      output: metadataOnlyOutput,
      messages: messages,
      usage: usage,
      finishReason: finishReason,
      resultMetadata: resultMetadata,
    );
  }

  /// Creates a ChatResult for non-streaming scenarios (e.g., tool-only).
  ChatResult<ChatMessage> createNonStreamingResult({
    required String responseId,
    required List<Part> parts,
    required Map<String, Object?> messageMetadata,
    required LanguageModelUsage usage,
    required FinishReason finishReason,
    required Map<String, Object?> resultMetadata,
  }) {
    final message = ChatMessage(
      role: ChatMessageRole.model,
      parts: parts,
      metadata: messageMetadata,
    );

    return createResult(
      responseId: responseId,
      output: message,
      messages: [message],
      usage: usage,
      finishReason: finishReason,
      resultMetadata: resultMetadata,
    );
  }
}
