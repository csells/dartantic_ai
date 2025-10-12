# Google Provider Migration Plan

## Objective
Replace usage of the deprecated `google_generative_ai` SDK with the generated `google_cloud_ai_generativelanguage_v1` package while keeping the dartantic Google provider’s public surface (providers/models/mappers) and all existing tests unchanged.

The implementation of the generated package is here: /Users/csells/temp/google-cloud-dart/generated/google_cloud_ai_generativelanguage_v1/lib/generativelanguage.dart

---

- [x] **1. Dependencies**  
  Specs: `wiki/Provider-Implementation-Guide.md`, `wiki/Unified-Provider-Architecture.md`  
  External refs: `/Users/csells/temp/google-cloud-dart/generated/google_cloud_ai_generativelanguage_v1/lib/generativelanguage.dart`  
  - Removed `google_generative_ai` from `packages/dartantic_ai/pubspec.yaml`.  
  - Added generated client + required deps: `google_cloud_ai_generativelanguage_v1`, `google_cloud_protobuf`, `google_cloud_gax`, `google_cloud_longrunning`, `google_cloud_rpc`.  
  - Added `dependency_overrides` pointing to the generated repo so we can iterate before publication.

- [x] **2. Shared Mapping Utilities**  
  Specs: `wiki/Message-Handling-Architecture.md` (Tool Result Handling), `wiki/Typed-Output-Architecture.md`  
  External refs: same generated file for proto types  
  - Added `protobuf_value_helpers.dart` for Map ⇄ `gl.Struct`/`gl.Value` conversions.  
  - Added `google_schema_helpers.dart` for JSON Schema → `gl.Schema`.  
  - Extended safety-setting mappers to return `gl.SafetySetting` / `gl.HarmCategory`.

- [x] **3. Message Mappers**  
  Specs: `wiki/Message-Handling-Architecture.md`, `wiki/Streaming-Tool-Call-Architecture.md`  
  External refs: `gl.Content`, `gl.Part`, `gl.FunctionCall`, `gl.FunctionResponse`, `gl.Candidate` in generated client  
  - Replaced mapper conversions with generated proto classes.  
  - Preserved tool-result batching (`ToolIdHelpers`, `return_result` filtering).  
  - Added finish-reason mapping for new enum members.

- [x] **4. Chat Model Implementation**  
  Specs: `wiki/Provider-Implementation-Guide.md`, `wiki/Orchestration-Layer-Architecture.md`, `wiki/Message-Handling-Architecture.md`  
  External refs: `GenerativeService` + request/response types in generated client  
  - Swapped `GenerativeModel` for `gl.GenerativeService` using `CustomHttpClient`.  
  - Build `gl.GenerateContentRequest` per send (system instructions, safety, schema, tool config).  
  - Stream via `streamGenerateContent` and convert chunks into `ChatResult`.  
  - Removed bespoke client caching.

- [x] **5. Embeddings Model**  
  Specs: `wiki/Provider-Implementation-Guide.md` (Embeddings), `wiki/Unified-Provider-Architecture.md`  
  External refs: `gl.EmbedContentRequest`, `gl.BatchEmbedContentsRequest`  
  - Use generated service for query + batch embeddings.  
  - Retained batching/token estimation logic.  
  - Continued using `CustomHttpClient` for auth headers.

- [x] **6. Provider Layer**  
  Specs: `wiki/Unified-Provider-Architecture.md`, `wiki/Provider-Implementation-Guide.md`  
  External refs: `gl.ModelService.listModels`  
  - Preserved public ctor, caps, aliases.  
  - Instantiated new chat/embedding models with existing params.  
  - Replaced `listModels()` HTTP call with generated `ModelService`.  
  - Verified base URL override path via `CustomHttpClient`.

- [ ] **7. Cleanup & Validation** *(in progress)*  
  Specs: `wiki/Test-Spec.md`  
  - Remove any lingering `google_generative_ai` imports (complete audit still pending).  
  - Run targeted suites:  
    1. `dart test packages/dartantic_ai/test/tool_calling_test.dart`  
    2. `dart test packages/dartantic_ai/test/chat_models_test.dart`  
    3. `dart test packages/dartantic_ai/test/streaming_test.dart`  
    4. `dart test packages/dartantic_ai/test/multi_provider_test.dart`  
    5. `dart test packages/dartantic_ai/test/embeddings_test.dart`  
    6. `dart test packages/dartantic_ai/test/provider_discovery_test.dart`  
  - Smoke-test `packages/dartantic_ai/example/bin/multi_turn_chat.dart` with a Gemini model.  
  - **Current status:** test runs are failing early due to missing/invalid provider API keys during migration; stabilizing the suite is the highest priority hand-off item.

- [ ] **8. Follow-Up**  
  Specs: `wiki/Architecture-Best-Practices.md` (documentation hygiene)  
  - Revisit TODOs that skip Google (e.g., `tool_calling_test.dart:540`) once tests are green.  
  - Document dependency changes in `packages/dartantic_ai/CHANGELOG.md` and `docs/providers.mdx`.

- [ ] **9. Add support for Gemini thinking** *(blocked on API surface)*  
  Specs: `wiki/Message-Handling-Architecture.md` (“Thinking Metadata”), `wiki/Orchestration-Layer-Architecture.md`  
  External refs: generated client currently exposes no explicit reasoning/thinking stream; confirm latest Gemini docs before implementation.  
  - Investigate how the new API surfaces reasoning/thinking metadata.  
  - Add provider cap, plumb `metadata['thinking']`, update `thinking.dart`.  
  - Ensure `thinking_metadata_test.dart` passes for Gemini.

- [ ] **10. Add support for Gemini prompt caching** *(blocked on API docs)*  
  Specs: none specific; `wiki/Streaming-Tool-Call-Architecture.md` mentions caching at orchestration level.  
  - Research Gemini prompt caching/session APIs (analogous to OpenAI Responses).  
  - Expose options in `GoogleChatModelOptions` (default to true), wire into requests.  
  - Add parity tests covering single- and multi-provider flows.

---

### Previous Work References
- Generated Google client: `/Users/csells/temp/google-cloud-dart/generated/google_cloud_ai_generativelanguage_v1/lib/generativelanguage.dart` (sidekick output, includes `GenerativeService`, `ModelService`, `EmbedContentRequest`, etc.).  
- Shared helper additions:  
  - `packages/dartantic_ai/lib/src/chat_models/helpers/protobuf_value_helpers.dart`  
  - `packages/dartantic_ai/lib/src/chat_models/helpers/google_schema_helpers.dart`
- Updated implementations:  
  - `packages/dartantic_ai/lib/src/chat_models/google_chat/google_chat_model.dart`  
  - `packages/dartantic_ai/lib/src/chat_models/google_chat/google_message_mappers.dart`  
  - `packages/dartantic_ai/lib/src/embeddings_models/google_embeddings/google_embeddings_model.dart`  
  - `packages/dartantic_ai/lib/src/providers/google_provider.dart`

### Outstanding Risks / Next Steps
1. **Fix test harness failures** – export provider API keys (`packages/dartantic_ai/example/.env`) and re-run suites above to ensure no regressions.  
2. **Thinking & prompt caching** – pending clarity on Gemini API surface; watch for updates to generated client or cloud docs.  
3. **Documentation & changelog** – update once tests pass and feature gaps are resolved.  
4. **Audit for leftover `google_generative_ai` imports** – ensure full removal across repo.
