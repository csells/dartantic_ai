# CODEx Task List — OpenAI Responses Provider

This document is a **coding-only milestone plan** for implementing the
`OpenAIResponsesProvider` in `dartantic_ai`. It is optimized for GPT‑5‑Codex
execution (minimal prompts, `apply_patch` usage, small toolset).

---

## Global Constraints

- Dart SDK **3.8** minimum; strict analyzer, follow repo lint rules.  
- **Dependency**: `openai_core: ^0.4.0`.  
- **API keys**: constructor uses `tryGetEnv('OPENAI_API_KEY')`; validate at model
  creation only.  
- **Default models**: chat=`gpt-4o`, embeddings=`text-embedding-3-small` (config
  overridable).  
- **Capabilities**: `{chat, embeddings, multiToolCalls, typedOutput,
  typedOutputWithTools, thinking, vision}`.  
- **Session persistence**: default `store=true`, persist metadata under
  `"_responses_session"`.  
- **Message history**: must pass `validateMessageHistory()`.  
- **Tool IDs**: use `tool_id_helpers.dart` when provider doesn’t supply IDs.  
- **Error handling**: exception transparency.  
- **Logging**: INFO for lifecycle, FINE for event detail.  
- **Examples**: `thinking.dart`, `server_side_tools.dart`, multi‑modal demo must
  run unchanged.

---

## Milestones

### M0 — Workspace & Baselines
- Update `pubspec.yaml` with SDK floor and dependency.
- Ensure `RetryHttpClient` and `Logger` available.

### M1 — Provider Skeleton & Registration
- File: `src/providers/openai_responses_provider.dart`
- Implement `OpenAIResponsesProvider` with identity, defaults, caps.
- Implement `createChatModel` and `createEmbeddingsModel` (API key validation
  only here).
- Register provider in `providers.dart`.

### M2 — Options Types
- File: `src/chat_models/openai_responses/openai_responses_chat_options.dart`.
- Class: `OpenAIResponsesChatOptions` with fields (temperature, topP, reasoning,
  toolChoice, store, intrinsic tool configs, etc.).
- File: `src/embeddings_models/openai_responses/..._embeddings_model.dart`.
- Class: `OpenAIEmbeddingsModelOptions` with dimensions, encoding, user,
  batchSize.

### M3 — Module Layout Scaffolding
- Create stubs for all module files: chat model, message mapper, event mapper,
  embeddings model, metadata helper.

### M4 — Message Mapping
- Implement `OpenAIResponsesMessageMapper.toResponsesInput(...)`.
- Support session replay scanning (`_responses_session`), multimodal mapping,
  validate history.

### M5 — Event Mapping
- Implement `OpenAIResponsesEventMapper` to translate SSE events →
  `ChatResult`.
- Handle text deltas, reasoning metadata, tool call/results, intrinsic tool
  telemetry, usage tokens.

### M6 — Chat Model
- Implement `OpenAIResponsesChatModel` with `sendStream(...)`.
- Merge options, construct `ResponsesSessionController`, feed mapper output,
  consume events via event mapper.
- Persist session state snapshot to metadata.

### M7 — Metadata Helpers
- File: `src/shared/openai_responses_metadata.dart`.
- Helpers for encoding/decoding `SessionStateSnapshot` and attaching to
  messages.

### M8 — Intrinsic Tools
- Extend event mapper to track telemetry for web search, file search, image
  generation, computer use, local shell, MCP, code interpreter.
- Expose `containerId` + file metadata; rely on existing helper for downloads.

### M9 — Typed Output
- When `outputSchema` present, use `TextFormatJsonSchema`.
- Support partial JSON streaming; no `return_result` tool injection.

### M10 — Embeddings Model
- Implement `OpenAIEmbeddingsModel` with `embedQuery` and
  `embedDocuments`.
- Use `OpenAIClient.createEmbeddings`; propagate usage/errors.

### M11 — Unit Tests
- Message mapper, event mapper, session persistence, embeddings model.

### M12 — Integration Tests
- Streaming + thinking metadata, typed output with tools, code interpreter
  container/file download, server‑side tools telemetry.

### M13 — Provider Discovery & Caps
- Verify registry lookup, caps discovery.

### M14 — Examples Verification
- Ensure `thinking.dart`, `server_side_tools.dart`, multimodal demo work with
  provider.

### M15 — Error Handling & Logging
- Confirm exception transparency and correct logging namespaces.

### M16 — Final Acceptance
- Check spec coverage and run all tests/examples.

---

## Codex Execution Notes
- Use **minimal dev prompts**, avoid preambles.  
- Use `apply_patch` for file edits.  
- Keep tool descriptions concise.  
