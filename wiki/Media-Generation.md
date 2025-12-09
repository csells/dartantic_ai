# Media Generation Specification

## Overview

This document defines a provider-agnostic **media generation** capability for
DartAntic. Any provider that can synthesize downloadable or streamable assets
(images, PDFs, Markdown, audio clips, etc.) exposes a `MediaGenerationModel`
alongside its chat and embeddings models. The Agent consumes these models to
produce media artifacts using the same prompt, context, and streaming semantics
already established for conversational flows.

Media generation is the unified abstraction that replaces legacy image-only
pipelines. Providers may continue to offer compatibility wrappers for older
APIs, but new integrations should implement this specification directly.

## Goals

1. Establish a first-class `MediaGenerationModel` contract that mirrors the
   streaming pattern of `ChatModel.sendStream` while accommodating
   media-specific requirements.
2. Allow providers to advertise support through a dedicated capability flag and
   supply default model names for the `media` model kind.
3. Enable the Agent to resolve `media=` selectors in the model string, cache the
   provider-specific instance, and expose `generateMedia` convenience helpers.
4. Preserve incremental delivery of binaries, hosted links, metadata, usage
   accounting, and chat transcripts so client applications can offer responsive
   experiences.

## Non-Goals

- Standardising the set of options exposed by individual providers. Each
  provider may define its own `MediaGenerationModelOptions` subtype.
- Mandating synchronous generation. Both streamed and bursty delivery are
  supported as long as progress is observable through emitted chunks.
- Providing emulation layers for providers that lack native media generation
  endpoints.

## `MediaGenerationModel` Contract

```dart
abstract class MediaGenerationModel<TOptions extends MediaGenerationModelOptions> {
  MediaGenerationModel({
    required this.name,
    required this.defaultOptions,
  });

  final String name;
  final TOptions defaultOptions;

  Stream<MediaGenerationResult> generateMediaStream(
    String prompt, {
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    TOptions? options,
    JsonSchema? outputSchema,
    required List<String> mimeTypes,
  });

  void dispose();
}
```

Key expectations:

- **Prompt Surface:** The method accepts a prompt plus optional chat history and
  structured attachments (`Part`s). This matches the Agent’s existing
  conversational inputs so media runs can leverage the same context and
  toolchain.
- **Options:** Providers extend `MediaGenerationModelOptions` with knobs such as
  size, duration, aspect ratio, safety settings, or style presets. Callers may
  override the defaults supplied by the model.
- **Requested MIME Types:** `mimeTypes` is a required list of acceptable output
  formats. Providers must validate the list, map it to upstream APIs, and reject
  unsupported combinations with descriptive errors.
- **Output Schema:** When present, `outputSchema` should be forwarded to
  providers that support schema-constrained outputs (e.g., Markdown fragments or
  JSON payloads). Providers that do not honour schemas may ignore the value but
  must document the limitation.
- **Streaming:** The stream yields intermediate `MediaGenerationResult` values.
  Providers should emit lightweight progress or metadata chunks rather than
  buffering large assets, and must mark the terminal chunk with `isComplete =
  true`.

### `MediaGenerationResult`

Each chunk emitted by `generateMediaStream` packages the latest state of the
run:

- `List<Part> assets`: Binary or textual payloads tagged with MIME types and
  filenames when available.
- `List<LinkPart> links`: Hosted URLs (for example, CDN locations or signed
  downloads) plus optional MIME hints.
- `List<ChatMessage> messages`: Any conversational messages generated during the
  run, including tool traces or reasoning updates.
- `Map<String, dynamic> metadata`: Cumulative metadata such as progress,
  warnings, tool execution summaries, or provider-specific annotations. Each
  emission should merge new metadata into the previously reported snapshot.
- `LanguageModelUsage? usage`: Token, compute, or credit consumption metrics. If
  only aggregate usage is available, emit it on the terminal chunk.
- `bool isComplete`: Signals the final chunk. The Agent uses this flag to
  aggregate the result for convenience wrappers.

## Provider Responsibilities

### Capability Signalling

- Providers that support media generation must implement `createMediaModel`,
  mirroring the chat and embeddings factories. Providers that cannot generate
  media should throw a clear `UnsupportedError`. Use `Provider.listModels()` at
  runtime to discover which models support media generation via `ModelKind.media`.
- Advertise default model names by extending `Provider.defaultModelNames` with a
  `ModelKind.media` entry. Providers may publish multiple media-capable models
  and should document their MIME coverage.

### Model Factory

- Implement `createMediaModel({String? name, TOptions? options})` so the Agent
  can instantiate media-capable models lazily. The factory may wrap existing
  transports (e.g., a chat streaming pipeline) or call dedicated media APIs.
- The returned model must respect the requested MIME types, surface provider
  options, and integrate with any required authentication or project settings.

### MIME-Type Negotiation

- Validate `mimeTypes` before invoking upstream APIs. When providers can toggle
  formats dynamically, translate the list into API-specific parameters. When the
  output format is fixed, document the accepted values and reject unsupported
  requests immediately.
- If the upstream API occasionally returns a different MIME type than requested,
  the provider must update the emitted `Part`/`LinkPart` to reflect the actual
  type so clients can handle it correctly.

### Server-Side Tooling and Orchestration

- **OpenAI Responses:** Image and asset synthesis requires enabling the
  `image_generation` server-side tool and selecting a Responses model that
  advertises the `image` modality. The media model should configure these
  defaults automatically and stream binary payloads (either inline base64 or
  hosted URLs) alongside metadata updates.
- **Google Gemini:** Gemini 2.5 supports native image generation via
  `responseModalities` and code execution for non-image file types. The media
  model routes image requests through native Imagen APIs and non-image requests
  (PDF, CSV, text files) through code execution. All file types are fully
  supported and returned as `DataPart`s.
- **Anthropic Claude:** Claude supports media generation via its **Code Interpreter**
  (Analysis) tool. The provider automatically enables the tool and instructs the
  model to generate files (e.g., PDFs, images) by writing and executing code.
  The resulting files are streamed as `Part`s in the `MediaGenerationResult`.

Providers integrating additional ecosystems (e.g., Stability AI, local diffusion
servers) should adopt the same behaviours: negotiate MIME types, surface
progress, and stream assets incrementally.

### Metadata and Usage Reporting

- Each emitted chunk should merge metadata into a cumulative map so the terminal
  chunk contains the full context of the run.
- Populate `LanguageModelUsage` whenever upstream services provide token counts,
  credit consumption, or compute measurements. When only aggregate data is
  available, emit it on the final chunk.

## Agent Integration

1. **Model Resolution:** Extend `ModelStringParser` to recognise a `media`
   selector. Resolution priority: explicit `media=` override, then the
   provider’s default media model, then optional fallbacks documented by the
   provider.
2. **Lifecycle:** Cache the lazily created media model on the Agent, mirroring
   chat and embeddings lifecycles, and dispose it when the Agent shuts down.
3. **API Surface:** Add `Future<MediaGenerationModelResult> generateMedia(...)`
   and `Stream<MediaGenerationResult> generateMediaStream(...)` helpers that:
   - Verify the provider advertises the media capability.
   - Forward prompt, history, attachments, schema, MIME types, and option
     overrides.
   - Aggregate streamed chunks into a final `MediaGenerationModelResult` for the
     convenience wrapper.
4. **Error Semantics:** Throw a descriptive `UnsupportedError` when the provider
   lacks media support. Propagate provider-specific errors (e.g., unsupported
   MIME types) so SDK and CLI callers can react appropriately.
5. **Tool Inference:** When a provider requires auxiliary tools or configuration
   (such as OpenAI’s server-side tools), the Agent should continue to enable
   them automatically based on the selected provider and model so callers do not
   need to micromanage tool lists.

## Compatibility and Migration

- Existing image-only surfaces may wrap a `MediaGenerationModel` and restrict
  the MIME list to image types for backwards compatibility. New development
  should prefer the media abstraction directly.
- Documentation, samples, and SDKs should highlight the `media=` selector and
  demonstrate requesting multiple MIME outputs in a single call when supported.
- Once all providers implement the media capability, legacy image-generation
  flags can be deprecated in favour of the unified model kind.

## Testing Strategy

- **Unit Tests:** Validate model string parsing, capability flags, MIME
  negotiation, and error paths. Ensure streamed chunks merge metadata and toggle
  `isComplete` correctly.
- **Integration Tests:** Run provider-specific scenarios that request multiple
  MIME types (for example, PNG plus WEBP, or Markdown plus PDF) and verify
  assets arrive incrementally.
- **Contract Tests:** Share fixtures that assert each emitted chunk includes at
  least one asset or link, exposes metadata maps, and never leaves the stream
  without a terminal `isComplete` chunk.

## Future Work

- Extend the abstraction to cover audio, video, and long-form document synthesis
  as providers release stable APIs.
- Standardise option schemas (e.g., `MediaStyleOptions`) for consistent UX
  across providers.
- Investigate resumable uploads/downloads for large artifacts and progress
  recovery after transient failures.
