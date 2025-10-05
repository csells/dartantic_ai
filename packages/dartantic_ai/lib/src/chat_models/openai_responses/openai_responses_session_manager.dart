import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../shared/openai_responses_metadata.dart';

/// Manages session metadata for OpenAI Responses API persistence.
///
/// Handles building and extracting session metadata that enables the Responses
/// API to maintain conversation continuity across requests.
class OpenAIResponsesSessionManager {
  /// Creates a new session manager.
  const OpenAIResponsesSessionManager();

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.session_manager',
  );

  /// Builds session metadata for message persistence.
  ///
  /// When [storeSession] is true, creates metadata containing the response ID
  /// that can be used to continue the conversation in future requests.
  Map<String, Object?> buildSessionMetadata({
    required openai.Response response,
    required bool storeSession,
  }) {
    final metadata = <String, Object?>{};
    if (storeSession) {
      _logger.info('━━━ Storing Session Metadata ━━━');
      _logger.info('Response ID being stored: ${response.id}');
      OpenAIResponsesMetadata.setSessionData(
        metadata,
        OpenAIResponsesMetadata.buildSession(responseId: response.id),
      );
      _logger.info('Session metadata saved to model message');
      _logger.info('');
    }
    return metadata;
  }

  /// Builds result metadata for ChatResult.
  ///
  /// Extracts response-level information like response ID, model, and status
  /// that should be included in the ChatResult metadata (not message metadata).
  Map<String, Object?> buildResultMetadata(openai.Response response) => {
    'response_id': response.id,
    if (response.model != null) 'model': response.model!.toJson(),
    if (response.status != null) 'status': response.status,
  };
}
