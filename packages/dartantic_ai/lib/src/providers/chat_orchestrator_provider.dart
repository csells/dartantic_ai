import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';

import '../agent/orchestrators/streaming_orchestrator.dart';

/// Interface for chat models that provide orchestrators.
abstract interface class ChatOrchestratorProvider {
  /// Selects the appropriate orchestrator and tools for this model.
  ///
  /// The tools list may be modified by the provider, e.g. Anthropic injects
  /// the return_result tool for typed output.
  (StreamingOrchestrator, List<Tool>?) getChatOrchestratorAndTools({
    required JsonSchema? outputSchema,
    required List<Tool>? tools,
  });
}
