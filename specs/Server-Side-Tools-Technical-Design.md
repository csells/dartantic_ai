# Server-Side Tools – Technical Design

## Overview

This document describes how dartantic enables provider-native, server-side tools (e.g., OpenAI Responses built-ins) and surfaces their usage via message metadata without requiring app-side execution.

Goals

- Enable/disable server-side tools per agent in a provider-agnostic way.
- Preserve native, single-round-trip execution semantics and streaming.
- Expose structured observability for UI/analytics/governance.
- Remain backward compatible with existing tool-calling flows.

Non-goals

- Re-implement provider tools on the client.
- Force built-ins into function-tool call/response cycles.

## API Surface

### OpenAI Responses Model Options

- `OpenAIResponsesChatOptions(serverSideTools: Set<OpenAIServerSideTool>)`
- Optional per-tool config: `fileSearchConfig`, `webSearchConfig`.

Behavior

- The set is mapped to native built-ins in the Responses request (e.g., `type: "web_search"`).
- Unrelated providers ignore these options (they are specific to Responses).

### Provider-Specific Configuration

For OpenAI Responses, we support:

- `OpenAIServerSideTool` enum for tool selection.
- `OpenAIResponsesChatOptions.serverSideTools` for enabling tools.
- `OpenAIResponsesChatOptions.fileSearchConfig` and `webSearchConfig` for tuning.
- Legacy: `builtInTools` container remains for backward compatibility, but prefer the fields above.

### Observability via Metadata

During streaming, built-in tool events are exposed as metadata-only updates:

- Keys: `web_search`, `file_search`, `computer_use`, `code_interpreter`.
- Structure: `{ stage: 'started' | 'result' | 'action', data: <event-payload> }`.
- Image generation: streamed via `LinkPart` or `DataPart` (plus metadata when applicable).

Rationale: keep tool outputs flowing directly to the model while giving apps hooks for progress, logging, and policy.

## OpenAI Responses Mapping

Request payload:

- Include native built-ins under `tools`: `{ "type": "web_search", "name": "web_search" }`, etc.
- Continue to include user function tools (`type: function`).

SSE handling:

- Recognize built-in events (e.g., `response.web_search.started`, `response.web_search.result`, `response.code_interpreter.output`, `response.image_generation.delta/completed`).
- Emit metadata-only `ChatResult` slices for non-text events; stream media via parts where appropriate.

## Compatibility with Function Tools

- Unchanged: function tools remain app-executed and return via tool results.
- When switching providers mid-turn, `previous_response_id` is used only for function_call_output linking; built-ins do not require it.

## Performance & Reliability

- Benefits: single round-trip, streamed artifacts, no extra HTTP for tool outputs.
- Failure handling: tool errors surface via SSE `response.error`; the client may observe metadata and handle UI fallbacks.

## Security & Governance

- Metadata enables audit logging and UI disclosures (e.g., “searching web”).
- App may filter prompts or disable certain built-ins via `serverSideTools`.

## Testing Strategy

- Unit tests for request shaping (tools array contains built-ins; union logic in Agent).
- SSE event parsing tests for metadata exposure.
- Manual/integration tests against OpenAI Responses for media events and end-to-end behavior.
