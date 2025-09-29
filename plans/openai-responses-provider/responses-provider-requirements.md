# OpenAI Responses Provider Requirements

## 1. Objectives
- Introduce a first-class `OpenAIResponsesProvider` that uses the OpenAI
  **Responses** API exclusively (no completions fallback) via the `openai_core`
  package.
- Achieve feature parity with existing dartantic providers (chat, streaming,
  multi-tool calls, typed output, embeddings) while adding Responses-specific
  capabilities (reasoning/thinking metadata, intrinsic server-side tools,
  session reuse, code interpreter containers, downloading files from the code
  container).
- Maintain idiomatic dartantic ergonomics: standard provider discovery, options
  classes, orchestrator compatibility, and metadata conventions.

## 2. Scope & Out of Scope
**In scope**
- New provider + models, provider registration, capability reporting, and
  environment configuration.
- Chat streaming built on `ResponsesSessionController`, including session
  persistence and history hydration.
- Support for all intrinsic Responses tools (web search, file search, image
  generation, computer use, MCP, local shell, code interpreter).
- Vision/multi-modal chat input (image/file/audio attachments) handled through
  the Responses API payload shapes.
- Embeddings via `/embeddings` endpoint using `openai_core`.
- Metadata surfacing for reasoning (“thinking”), tool progress, usage, response
  IDs, etc.
- Tests, examples, and documentation updates reflecting the new provider.

**Out of scope (for now)**
- GUI or CLI helpers for downloading container files (examples can show usage
  via helper functions).

## 3. Provider Identity & Registration
- Register the provider in
  `packages/dartantic_ai/lib/src/providers/providers.dart` with the prefix
  `openai-responses` and an appropriate display name (e.g., "OpenAI Responses").
- Reuse existing environment conventions: `OPENAI_API_KEY`, `OPENAI_BASE_URL`
  (if present), additional headers.
- Default model names:
  - Chat: `gpt-4o` (adjust if we discover a better Responses default).
  - Embeddings: `text-embedding-3-small`.
- Capabilities to advertise: `{chat, embeddings, multiToolCalls, typedOutput,
  typedOutputWithTools, thinking, vision}`.
- Implement `listModels()` using `openai_core`'s client; surface `ModelKind`
  sets similar to the existing OpenAI provider.
- Must be discoverable via `Providers.get('openai-responses')` and
  `Providers.allWith({ProviderCaps.thinking})`.
- Provider constructor must use lazy initialization pattern - API key validation
  only at model creation time, not constructor time.

## 4. Dependencies & Packaging
- Add `openai_core` to `packages/dartantic_ai/pubspec.yaml` with the most recent
  version.
- No reuse of existing `openai_chat` or embeddings code; create dedicated files
  (e.g., `openai_responses_provider.dart`, `openai_responses_chat_model.dart`,
  `openai_responses_embeddings_model.dart`).
- Ensure the new code stays within the workspace write boundaries and follows
  ASCII-only defaults.

## 5. Chat Model Implementation
### 5.1 Controller Usage
- Instantiate `OpenAIClient` from `openai_core` with the resolved API key/base
  URL.
- Construct a `ResponsesSessionController` per `sendStream` call, feeding it:
  - `input`: derived from the incoming `List<ChatMessage>` history
    (system/user/model) converted to `ResponseInputItems`, including mapping
    text, image (inline/base64 or URL), and other binary attachments
    (`DataPart`/`LinkPart`) into the appropriate `InputMessage` content
    structures.
  - `tools`: Responses tool metadata built from dartantic tool definitions +
    server-side tool options (see §6).
  - Options (temperature, top-p, reasoning, metadata includes, `store`,
    `parallel_tool_calls`, `tool_choice`, instructions, etc.) sourced from
    `OpenAIResponsesChatOptions`.
- When `store == true`, pull `previousResponseId` from the latest model message
  metadata. Note: Pending outputs are always empty in dartantic because the
  orchestrator executes all tools synchronously, unlike ResponsesSessionController
  which may have async tool executions. Persist controller updates back into
  metadata (below).
- Default the controller to `store = true` unless the caller explicitly opts
  out so that Responses sessions remain server-side by default.

### 5.2 Streaming & Message Mapping
- Consume `controller.serverEvents` until `ResponseCompleted`.
- For each event:
  - Aggregate `response.output_text.delta` to build chunk output strings and
    final message text.
  - Handle `response.output_item.*` and `response.content_part.*` to assemble
    `ChatMessage` parts at the right granularity.
  - Translate tool call/result items into `ToolPart` instances the orchestrator
    can use for tool execution.
- Yield `ChatResult<ChatMessage>` chunks in sync with dartantic orchestrators:
  - Non-empty `result.output` → streaming text chunk (respect leading newline
    rules from `DefaultStreamingOrchestrator`).
  - Completed message parts → `result.messages` entries with consolidated
    `ChatMessage` objects.
  - Always carry forward `metadata`, `usage`, `finishReason`, and `id`.
- Ensure `model.dispose()` closes the `OpenAIClient` and SSE stream.
- Streamed chunks must accumulate into coherent complete responses.
- Tool results must integrate properly into message history during streaming.
- Must pass dartantic's `validateMessageHistory()` utility function.
- System messages only allowed at index 0, strict user/model/user/model
  alternation thereafter.

### 5.3 Thinking Metadata
- Capture all reasoning-related events:
  - `response.reasoning_summary_text.delta/done`,
    `response.reasoning_summary.delta/done`, `response.reasoning.delta/done`.
- Produce a single human-readable trace (concatenate summaries + deltas) and
  expose it as `metadata['thinking']` on both streamed chunks and final
  messages.
- Preserve structured details (e.g., encrypted reasoning references) under
  `metadata['thinking_details']` or similar for advanced consumers.

### 5.4 Session Persistence
- When `store` is true, persist the following into the latest model message
  metadata:
  - `previous_response_id` from the controller.
  - An empty `pending_items` list. Note: This field exists for compatibility but
    is always empty because dartantic's orchestrator executes all tools
    synchronously before the response completes.
- When `store` is false, rebuild the controller input each turn from the entire
  conversation history (`ResponseInputItems`) respecting message roles.
- Ensure instructions/system prompts are preserved when reconstructing the
  controller input.
- When replaying a stored session, scan the entire conversation history (most
  recent messages first) to locate the latest `previous_response_id`. The
  associated pending outputs will always be empty since dartantic executes all
  tools synchronously. Include all intermediate model messages that have not yet
  been acknowledged by the Responses API so that the server state stays
  consistent even in multi-agent conversations.

## 6. Chat Options & Tool Configuration
- Create `OpenAIResponsesChatOptions extends ChatModelOptions` with fields for:
  - General parameters: `temperature`, `topP`, `maxOutputTokens`, `truncation`,
    `metadata`, `include`, `instructions`, `parallelToolCalls`, `reasoning`
    (`effort`, `summary detail`), `toolChoice`, `store`, `previousResponseId`
    override.
  - Text/typed-output control: ability to select `TextFormatJsonSchema` when a
    schema is supplied.
  - Intrinsic tool toggles/config:
    - Web search: `serverSideTools` enum set + search context size, user
      location metadata.
    - File search: vector store IDs, filters, ranking options, max results.
    - Image generation: model, background, size, quality, partial-images,
      moderation.
    - Computer use: display dimensions, environment, approval handling.
    - MCP: server URL/label, allowed tools, headers, approval policy.
    - Local shell: enable/disable.
    - Code interpreter: container settings (reuse ID, ephemeral config).
  - Custom headers / request metadata if needed by `openai_core` (e.g., project
    IDs).
- Ensure options default sensibly (e.g., `serverSideTools = {}`) and integrate
  with provider default options.
  - Multi-modal attachment encoding (image/data/file parts) should be mapped to
    Responses `Input` content, including detail selection for images.
- Default `store` to `true` in the options so that session persistence is the
  standard behavior for the provider.

## 7. Intrinsic Tool Support
For each Responses tool, implement mapping and metadata surfacing:
- **Web Search**: Stream `response.web_search_call.*` stages under
  `metadata['web_search'] = {stage, data}`; include preview results when
  available.
- **File Search**: Mirror stage metadata under `metadata['file_search']`; expose
  query/result snippets.
- **Image Generation**: Capture stage updates (skip noisy partials if desired)
  under `metadata['image_generation']` and transform generated images into
  `LinkPart`/`DataPart` message parts (base64 handling).
- **Computer Use**: Surface stage/action metadata under
  `metadata['computer_use']`; annotate screenshot outputs with file references.
- **MCP**: Track argument streaming, approvals, failures, and outputs under
  `metadata['mcp']`; convert final results to `ToolPart`.
- **Local Shell**: Expose progress and output under `metadata['local_shell']`.
- **Code Interpreter**: Handle code streaming, execution stages, result
  files/logs under `metadata['code_interpreter']`.
  - Include a list of generated files with IDs, filenames, and container IDs so
    clients can fetch content.

All tool call events must also translate into `ToolPart.call` /
`ToolPart.result` objects so orchestrators can trigger local tool handlers when
appropriate.

## 8. Code Interpreter Containers & Files
- Track active container ID in metadata after each code interpreter call.
- On subsequent turns, if history shows a container reuse request (metadata
  field) or options specify `containerId`, pass it through the controller.
- Document (and demonstrate via example) how to download container files using
  the stored metadata and `OpenAIClient` (or helper function similar to
  `downloadContainerFile`).

## 9. Typed Output & JSON Schema
- When an orchestrator supplies an `outputSchema`, automatically configure the
  request with `TextFormatJsonSchema` (name can default to `dartantic_output`).
- Ensure typed output works concurrently with tool calling by using Responses’
  native support (`typedOutputWithTools` capability).
- Remove the need for the `return_result` tool in this provider.

## 10. Embeddings Model
- Implement `OpenAIEmbeddingsModel` using
  `OpenAIClient.createEmbeddings`:
  - Accept `OpenAIEmbeddingsModelOptions` (dimensions, encoding format,
    user, batch size if needed).
  - Translate success into `EmbeddingsResult` with usage metadata.
  - Propagate `OpenAIRequestException` details on failure.
- Provide helper(s) to convert `EmbeddingModel` enums if necessary.

## 11. Metadata, Usage & Errors
- Include response ID, created timestamp, model name, and usage tokens in
  `ChatResult.metadata`/`usage` for every chunk.
- Bubble up `OpenAIRequestException` without suppression; map `code`, `message`,
  `param`, and HTTP status into dartantic's error structures.
- Add targeted logging (e.g., via
  `Logger('dartantic.chat.models.openai_responses')` and similar for embeddings)
  while avoiding noisy event-by-event logs unless at `FINE` level.
- Must follow dartantic's exception transparency principle - no try-catch blocks
  that suppress errors.

## 12. Testing Strategy
- Unit tests for:
  - Mapping of Responses SSE events to `ChatResult` (text streaming, tool calls,
    reasoning metadata, usage) using mocked events.
  - Session persistence flow (`store` true/false, `previousResponseId`,
    container reuse).
  - Intrinsic tool metadata decisions (web search, code interpreter file
    metadata, etc.).
  - Embeddings success/error paths.
- Provider discovery tests verifying capability flags and registry access
  (`Providers.get('openai-responses')`).
- Integration tests (or example-driven smoke tests) to ensure the provider can
  complete a round-trip chat with streaming and tool metadata (requires gating
  if tests need network access).

## 13. Documentation & Examples
- Add/update examples under `packages/dartantic_ai/example/bin/`:
  - Refresh `thinking.dart` and `server_side_tools.dart` to use the new provider
    prefix and APIs.
  - Provide a minimal Responses session example showcasing `store`, tool
    metadata, and thinking output.
- Update docs:
  - `docs/providers.mdx` table entries and capability descriptions.
  - `wiki/Home.md` (architecture overview) highlighting the new provider and
    `ProviderCaps.thinking` usage.
  - Any feature-specific docs (e.g., streaming, tool calling, typed output) to
    mention Responses behaviors.
- Note any new environment variables or configuration instructions if
  applicable.

## 14. Open Questions / Follow-ups
- Confirm whether Responses exposes any vision/multimodal capabilities worth
  flagging for future work.
- Evaluate need for helper APIs to simplify download of container files (could
  be added once core provider is stable).
