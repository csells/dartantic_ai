# Google Provider Migration Plan

## Objective
Replace usage of the deprecated `google_generative_ai` SDK with the generated `google_cloud_ai_generativelanguage_v1` package while keeping the dartantic Google provider’s public surface (providers/models/mappers) and all existing tests unchanged.

## 1. Dependencies
- Remove `google_generative_ai` from `packages/dartantic_ai/pubspec.yaml`.
- Add the generated package and any required transitive deps: `google_cloud_ai_generativelanguage_v1`, `google_cloud_gax`, `google_cloud_protobuf`, `google_cloud_longrunning`, `google_cloud_rpc`.
- Introduce a local `dependency_overrides` entry (path/git) so the generated package is available until it is published or vendored.

## 2. Shared Mapping Utilities
- Add helpers to convert between `Map<String, dynamic>` and protobuf `Struct`/`Value` for tool arguments & results (place with existing mapper helpers).
- Port JSON-schema → `Schema` conversion logic to the new protobuf types, preserving the same validation behavior.
- Extend safety-setting mappers to emit `SafetySetting` / `HarmCategory` enums based on current `GoogleChatModelOptions`.

## 3. Message Mappers
- Rewrite `google_message_mappers.dart` to target the generated `Content`, `Part`, `FunctionCall`, `FunctionResponse`, `Blob`, and `FileData` types.
- Keep tool-result grouping and tool-id assignment exactly as today (`ToolIdHelpers` and `return_result` filtering).
- Map `Candidate.finishReason` values (including new enum members) onto dartantic’s `FinishReason`.

## 4. Chat Model Implementation
- Replace `google_generative_ai.GenerativeModel` usage in `google_chat_model.dart` with a `GenerativeService` client constructed over `CustomHttpClient` so headers/retry logic stay centralized.
- Build `GenerateContentRequest` per send: extract system instructions, map history via the new mappers, assemble `GenerationConfig`, `SafetySetting`, tool declarations, and optional `ToolConfig` (code execution).
- Update streaming to call `streamGenerateContent`, translate each chunk into `ChatResult<ChatMessage>`, and preserve logging/usage metadata.
- Remove the old client caching that existed solely for system instruction updates.

## 5. Embeddings Model
- Replace calls to `GenerativeModel.embedContent` / `batchEmbedContents` with `GenerativeService.embedContent` / `batchEmbedContents`.
- Produce `EmbedContentRequest` batches with prior defaults (task type, dimensions, batching) and keep token-estimation behavior identical.
- Ensure `CustomHttpClient` continues to inject API key headers for both single and batch operations.

## 6. Provider Layer
- Keep `GoogleProvider`’s constructor, default models, caps, and aliases unchanged.
- Instantiate the refactored chat/embeddings models with the same parameters (`tools`, `temperature`, `options`, `baseUrl` overrides).
- Replace `listModels()` HTTP logic with `ModelService.listModels`, translating to `ModelInfo` using existing heuristics (kinds, metadata, logging, error handling).
- Verify provider-level `baseUrl` overrides still work; if the generated client hardcodes the host, extend `CustomHttpClient` or wrap `ServiceClient` to honor overrides.

## 7. Cleanup & Validation
- Remove all remaining `google_generative_ai` imports/usages across the repo.
- Run targeted tests that cover Google chat, embeddings, tools, streaming, and typed output:
  - `dart test packages/dartantic_ai/test/tool_calling_test.dart`
  - `dart test packages/dartantic_ai/test/chat_models_test.dart`
  - `dart test packages/dartantic_ai/test/streaming_test.dart`
  - `dart test packages/dartantic_ai/test/multi_provider_test.dart`
  - `dart test packages/dartantic_ai/test/embeddings_test.dart`
  - `dart test packages/dartantic_ai/test/provider_discovery_test.dart`
- Smoke-test examples (`packages/dartantic_ai/example/bin/multi_turn_chat.dart`) with a Gemini model to confirm behavior parity.

## 8. Follow-Up
- Revisit TODOs that skip Google tests (e.g., `tool_calling_test.dart:540`) once the migration lands.
- Document the dependency change in `CHANGELOG.md` and relevant docs (`docs/providers.mdx`) while noting that the API surface stayed stable.

## 9. Add support for gemini thinking
- investigate how thinking is configurated and exposed via the new generatied
  gemini API
- add support for thinking that exposes thinking as described in `thinking.mdx`
- update the google provider to exposes the thinking provider cap
- update the `thinking.dart` sample to work for gemini
- ensure the `thinking_metadata_test.dart` tests work for gemini

## 10. Add support for gemini prompt caching
- investigate how prompt caching aka session management works for the openai
  responses API
- investigate how prompt caching aka session management is exposes via the new
  generated gemini API
- enable prompt caching for gemini via google chat model options; default to
  true
- add tests to ensure that gemini prompt caching works for gemini the same way
  it works for the openai responses provider
- add tests to ensure that multi-provider chats with tool calls and typed output
  work with prompt caching enabled
