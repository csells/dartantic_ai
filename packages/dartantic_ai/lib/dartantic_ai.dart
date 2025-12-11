/// Compatibility layer for language models, chat models, and embeddings.
///
/// Exports the main abstractions for use with various providers.
library;

export 'package:dartantic_interface/dartantic_interface.dart';

export 'src/agent/agent.dart';
export 'src/agent/model_string_parser.dart';
export 'src/agent/orchestrators/orchestrators.dart';
export 'src/chat_models/chat_models.dart';
export 'src/embeddings_models/embeddings_models.dart';
export 'src/logging_options.dart';
export 'src/mcp_client.dart';
export 'src/media_gen_models/media_models.dart';
export 'src/providers/providers.dart';
