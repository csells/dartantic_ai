# Server-Side Tools Technical Design

This document describes the architecture and implementation patterns for server-side tools in Dartantic AI providers. Server-side tools are capabilities executed by the provider's infrastructure (not client-side) that stream progress events during execution.

## Table of Contents
1. [Overview](#overview)
2. [Generic Patterns](#generic-patterns)
   - [Metadata vs Message Output](#metadata-vs-message-output)
   - [Metadata Flow Pattern](#metadata-flow-pattern)
   - [Streaming Events](#streaming-events)
   - [Final Message Metadata](#final-message-metadata)
   - [Synthetic Summary Events](#synthetic-summary-events)
   - [Content Deliverables](#content-deliverables)
3. [Implementation Guidelines](#implementation-guidelines)
4. [OpenAI Responses Provider](#openai-responses-provider)
   - [Configuration](#configuration)
   - [Supported Tools](#supported-tools)
   - [Provider-Specific Details](#provider-specific-details)
5. [Testing Strategy](#testing-strategy)

## Overview

Server-side tools are capabilities provided by AI providers that execute on the provider's infrastructure rather than requiring client-side implementation. Unlike client-side tools (user-defined functions), server-side tools:

- Execute on the provider's infrastructure
- Are configured via provider-specific options
- Stream progress events during execution
- Require standardized metadata handling to expose their operation to applications

This document establishes generic patterns that apply across providers, with provider-specific details documented separately.

## Generic Patterns

The following patterns apply to all providers with server-side tools.


## Metadata vs Message Output

Understanding when server-side tool data appears in **metadata** versus **message output** (parts) is critical:

### The Principle

- **Metadata**: Progress information, intermediate states, tool execution details
- **Message Output**: Final deliverables that are part of the conversation content

### Why This Distinction Matters

Server-side tools often produce both:
1. **Process information**: How the tool executed, what steps it took
2. **Content deliverables**: Actual results that should be part of the message

The distinction ensures:
- Clean separation between "how it happened" (metadata) and "what was produced" (message content)
- Metadata is optional to consume - developers can ignore it if they only care about results
- Message content is always accessible through standard part iteration
- Conversation history remains clean and focused on actual content

### Metadata and Model Context

**Critical**: Metadata is **never** sent to the model. It exists purely for application/developer use. This means:
- ✅ Safe to keep in message history for debugging/transparency
- ✅ Safe to strip from messages before sending to reduce token usage
- ✅ Does not affect model behavior or responses
- ✅ Can contain verbose debugging information without cost

Developers can choose to:
- Keep metadata for full transparency and debugging
- Strip metadata to reduce memory/storage footprint
- Selectively preserve certain metadata fields

### Metadata: Partial/Progress Information

Metadata contains information about tool execution and intermediate states. Typical metadata includes:

- **Progress events**: in_progress, processing, completed
- **Intermediate states**: Partial results, status updates
- **Execution details**: What was searched, code executed, queries run

**Key characteristic**: Metadata is about the **journey** - it shows what the tool is doing or did.

### Message Output: Final Deliverables

Message parts contain final content that is part of the conversation. Content belongs in message parts when:

- The content is a primary deliverable (images, files, documents)
- Users will want to see/save/use it directly
- It should appear in conversation history naturally
- It's standalone content that makes sense without context

**Key characteristic**: Message parts are **deliverables** - they are the actual content being communicated.

### Examples by Tool Type

**Image Generation:**
- Metadata: Progress events, partial preview images
- Message Parts: Final generated image as `DataPart`
- Rationale: The image IS the response content

**Code Execution:**
- Metadata: Execution events, code, logs, results
- Message Parts: Text synthesis only
- Rationale: Code output is contextual, model synthesizes into natural language

**Search (Web/File):**
- Metadata: Search events, queries, results
- Message Parts: Text synthesis only
- Rationale: Search informs the text response

### Decision Matrix: Metadata vs Message Output

Use **message parts** when:
- ✅ The content is a primary deliverable (images, files)
- ✅ Users will want to see/save/use it directly
- ✅ It should appear in conversation history naturally
- ✅ It's standalone content that makes sense without context

Use **metadata** when:
- ✅ Showing tool execution progress/steps
- ✅ Providing debugging/transparency information
- ✅ Offering intermediate states (previews, partial results)
- ✅ Documenting what was searched/executed
- ✅ Content needs context from text to be meaningful

### Consistency Rules

1. **Both during streaming and final**: Structure should be the same
2. **Metadata accumulates**: Each streaming chunk adds to the event list
3. **Parts replace**: Final message parts replace any streaming parts
4. **No duplication**: Don't put the same content in both metadata and parts

## Metadata Flow Pattern

Server-side tool metadata follows the same pattern as thinking/reasoning metadata:

### Pattern Overview

```mermaid
flowchart LR
    A[Streaming Event] --> B[Internal Event Log]
    B --> C[Message Metadata]
    C -.not.-> D[Result Metadata]
```

This mirrors the thinking pattern:
- **During streaming**: Individual events emitted in `ChatResult.metadata`
- **Final result**: Complete event list in `ChatMessage.metadata`
- **Result metadata**: Does NOT include tool events (only response_id, model, status)

### Why This Pattern?

1. **Consistency**: Matches the established thinking metadata pattern
2. **Accessibility**: Tool events are part of the conversation history
3. **Developer ergonomics**: Same structure during streaming and in final message
4. **Separation of concerns**: Result metadata is for response-level info, message metadata is for content-level info

## Streaming Events

### Event Emission During Streaming

When a server-side tool event arrives, it's immediately emitted in the `ChatResult.metadata` as a **single-item list**.

**Algorithm:**
1. Identify the event type and determine which tool it belongs to
2. Convert the event to JSON
3. Wrap the JSON in a single-item list
4. Create a ChatResult with empty output and the list in metadata under the tool's key
5. Yield this chunk to the streaming response

### List Format

**Critical**: Metadata is ALWAYS a list, even during streaming with single events. This ensures:
- Consistent structure between streaming and final results
- Developer code works the same for both cases
- Easy to iterate over events without type checking

```dart
// Developer code works the same for streaming and final:
await for (final chunk in agent.sendStream(prompt)) {
  final events = chunk.metadata['web_search'] as List?;
  if (events != null) {
    for (final event in events) {
      final stage = event['type'];
      print('Stage: $stage');
    }
  }
}
```

### Event Accumulation

Events are accumulated in an internal event log map that tracks events for each tool type (web_search, file_search, image_generation, etc.).

**Algorithm:**
1. Maintain a map with keys for each tool type: 'web_search', 'file_search', 'image_generation', 'local_shell', 'mcp', 'code_interpreter'
2. Each key maps to a list of event objects (JSON maps)
3. When a server-side tool event arrives during streaming:
   - Convert the event to JSON
   - Append to the appropriate tool's list in the map
4. This accumulated log is used to build the final message metadata

## Final Message Metadata

### Building Message Metadata

When building the final result, complete event lists are copied from the internal event log to the message metadata.

**Algorithm:**
1. Create a message metadata map
2. If thinking/reasoning was captured, add it under 'thinking' key
3. Iterate through the internal event log map
4. For each tool that has non-empty event lists:
   - Copy the entire event list to message metadata under the tool's key
5. Attach this metadata map to the final ChatMessage

### Result Metadata (Does NOT Include Tool Events)

The `ChatResult.metadata` contains only response-level information (response_id, model, status). Tool events do NOT appear here - they only appear in the message metadata. This separation maintains clear distinction between response-level metadata and content-level metadata.

## Synthetic Summary Events

### Problem: Missing Data in Streaming Events

Some tools have additional data in `response.output` items that isn't available during streaming:

| Tool | Streaming Events Have | response.output Adds |
|------|----------------------|---------------------|
| WebSearch | Progress stages | Nothing (just id/status) |
| ImageGeneration | Partial images | resultBase64 (redundant) |
| FileSearch | Progress stages | **queries, results** |
| CodeInterpreter | Progress stages | **code, results, containerId** |
| MCP | Progress stages | Nothing |
| LocalShell | Command, output | Nothing |

### Solution: Append Synthetic Events

For tools with additional data (FileSearch and CodeInterpreter), append the `response.output` item as a synthetic final event to the message metadata.

**Algorithm:**
1. After all streaming events have been processed
2. Iterate through `response.output` items
3. For FileSearchCall items:
   - Create synthetic event with type: 'file_search_call'
   - Include id, queries, results, and status from the call
   - Append to the 'file_search' event list in message metadata
4. For CodeInterpreterCall items:
   - Create synthetic event with type: 'code_interpreter_call'
   - Include id, code, results, containerId, and status from the call
   - Append to the 'code_interpreter' event list in message metadata
5. Ignore all other output item types (no additional data beyond streaming events)

### Final Metadata Structure

The complete event list includes both streaming events and any synthetic summary events with additional data not available during streaming.

### Determining Which Tools Need Synthetic Events

For each tool, evaluate:
1. Does the provider's final response contain data not available during streaming?
2. Is this data valuable for debugging, transparency, or application logic?
3. If yes: append a synthetic summary event with the additional data

**Common examples:**
- File search: final queries and results
- Code execution: final code, outputs, execution context
- Multi-step processes: final summary of all steps

## Content Deliverables

Some server-side tools generate content that should appear as message parts, not just metadata.

### When to Create DataParts

Content should be added as a `DataPart` when:
1. It's the primary deliverable of the tool (images, documents, files)
2. It should persist in conversation history
3. Users expect to access it as message content

### Progressive Content (Partial Results)

For tools that support progressive rendering/generation:

**Algorithm:**
1. During streaming, track state:
   - Store partial content as it arrives
   - Each new partial may overwrite or append to previous
   - Set a completion flag when the completion event arrives
2. When building the final result:
   - Check if tool completed AND we have final content
   - Decode/process the content into appropriate format
   - Create a DataPart with the content and appropriate MIME type
   - Add the DataPart to the message parts list
3. Wait for completion event - only add DataPart after receiving it

### Why DataPart and Not Just Metadata?

1. **Semantic correctness**: Generated content is primary response material, not metadata
2. **Consistency**: Content from all sources should appear as parts
3. **Developer ergonomics**: Standard message part handling works uniformly
4. **History persistence**: Content naturally persists in conversation history

## Implementation Guidelines

### 1. Event Recording

**Algorithm:**
1. When a streaming event arrives, check its type
2. If it's a server-side tool event (web search, image generation, etc.):
   - Convert event to JSON
   - Append to the appropriate tool's list in internal event log
   - Yield a metadata chunk (see next section)

### 2. Metadata Emission

**Algorithm:**
1. Create a ChatResult with:
   - Empty output message (no parts)
   - Empty messages list
   - Metadata containing the event as a single-item list under the tool key
   - Empty usage stats
2. Yield this chunk to the stream

The single-item list format is critical for consistency with final metadata structure.

### 3. Final Metadata Assembly

**Algorithm:**
1. Create message metadata map
2. Add thinking metadata if present
3. For each tool in event log with non-empty events:
   - Copy complete event list to message metadata
4. Return this map as part of the final ChatMessage

### 4. Synthetic Event Appending

**Algorithm:**
1. After all streaming events processed
2. Iterate through provider's final response structure
3. For tools with additional data not in streaming events:
   - Extract the additional data
   - Create a synthetic summary event
   - Append to the tool's event list in message metadata
4. Ignore tools that have no additional data

See [Synthetic Summary Events](#synthetic-summary-events) section for details.

### 5. Content Deliverables

**Algorithm:**
1. During streaming: track partial content and completion status
2. When building final result: check completion flag
3. If completed: process content and add DataPart to message parts

See [Content Deliverables](#content-deliverables) section for details.

### 6. Non-Text Parts in Streamed Responses

**Algorithm:**
1. Check if text was streamed during response
2. If yes:
   - Filter message parts to separate text from non-text parts
   - Create output message with empty parts list (text already streamed)
   - Add output message metadata
   - If non-text parts exist: create separate message with only non-text parts
   - Return result with metadata-only output and non-text parts in messages
3. If no text was streamed:
   - Include all parts (text and non-text) in output message

## Developer Usage Patterns

### Consuming Tool Metadata During Streaming

```dart
await for (final chunk in agent.sendStream(prompt)) {
  if (chunk.output.isNotEmpty) stdout.write(chunk.output);

  // Access tool events (always a list)
  final toolEvents = chunk.metadata['tool_name'] as List?;
  if (toolEvents != null) {
    for (final event in toolEvents) {
      // Process event based on its structure
      final eventType = event['type'] as String?;
      // Handle event...
    }
  }
}
```

### Accessing Complete Tool History

```dart
final result = await agent.send(prompt);
final lastMessage = agent.messages.last;

// Tool metadata accumulated in message
final toolEvents = lastMessage.metadata['tool_name'] as List?;
if (toolEvents != null) {
  for (final event in toolEvents) {
    // Process complete event history
  }
}
```

### Handling Content Deliverables

```dart
await for (final chunk in agent.sendStream(prompt)) {
  // Check for content parts in messages
  for (final msg in chunk.messages) {
    for (final part in msg.parts) {
      if (part is DataPart) {
        // Handle generated content (images, files, etc.)
        processContent(part.bytes, part.mimeType);
      }
    }
  }
}
```

## OpenAI Responses Provider

This section contains OpenAI Responses API specific implementation details. The generic patterns defined above apply here, but this section documents the provider-specific configuration, event types, and behaviors.

Future providers with server-side tools should follow the same generic patterns while documenting their own provider-specific details in separate sections.

### Configuration

Server-side tools are configured when creating an Agent via `OpenAIResponsesChatModelOptions`:

```dart
final agent = Agent(
  'openai-responses:gpt-4o',
  chatModelOptions: OpenAIResponsesChatModelOptions(
    serverSideTools: {
      OpenAIServerSideTool.webSearch,
      OpenAIServerSideTool.imageGeneration,
    },
    webSearchConfig: WebSearchConfig(
      contextSize: WebSearchContextSize.medium,
      location: WebSearchLocation(city: 'Seattle', country: 'US'),
    ),
    imageGenerationConfig: ImageGenerationConfig(
      partialImages: 2,  // Request 2 progressive previews
      quality: ImageGenerationQuality.high,
      size: ImageGenerationSize.square1024,
    ),
  ),
);
```

### Supported Tools

- **Web Search**: Search the web for current information
- **Image Generation**: Generate images using gpt-image-1
- **File Search**: Search through uploaded files/vector stores
- **Code Interpreter**: Execute Python code with file handling
- **MCP (Model Context Protocol)**: Connect to MCP servers
- **Local Shell**: Execute shell commands server-side

**Note**: OpenAI's Responses API also provides a **Computer Use** tool for remote desktop/browser control, but this is currently out of scope for Dartantic and not implemented.

### Tool-Specific Configuration Classes

#### WebSearchConfig
- **contextSize**: Search context size (small, medium, large)
- **location**: User location metadata (city, region, country, timezone)

#### ImageGenerationConfig
- **partialImages**: Number of progressive previews (0-3, default: 0)
- **quality**: Image quality (low, medium, high, auto - default: auto)
- **size**: Image dimensions (square1024, portrait, landscape, etc. - default: auto)

#### FileSearchConfig
- **vectorStoreIds**: List of vector store IDs to search
- **maxResults**: Maximum number of results to return
- **ranker**: Ranking algorithm to use
- **scoreThreshold**: Minimum relevance score

#### CodeInterpreterConfig
- **shouldReuseContainer**: Whether to reuse previous container
- **containerId**: Specific container ID to reuse
- **fileIds**: Files to make available in container

### Provider-Specific Details

#### Event Types

OpenAI Responses uses event types like:
- `response.web_search_call.in_progress`
- `response.web_search_call.searching`
- `response.web_search_call.completed`
- `response.image_generation_call.partial_image`
- `response.code_interpreter_call.interpreting`

#### Synthetic Summary Events

Tools requiring synthetic events:
- ✅ **FileSearch**: Append `FileSearchCall` (has queries + results)
- ✅ **CodeInterpreter**: Append `CodeInterpreterCall` (has code + results + containerId)
- ❌ **WebSearch**: Ignore `WebSearchCall` (no additional data)
- ❌ **ImageGeneration**: Ignore `ImageGenerationCall` (resultBase64 redundant)
- ❌ **MCP**: Ignore `McpCall` (no additional data)
- ❌ **LocalShell**: Ignore `LocalShellCall` (no additional data)
- 🚫 **ComputerUse**: Not supported (out of scope for Dartantic)

#### Image Generation Details

When `partialImages > 0`, the API streams intermediate render stages:
1. Track each `ResponseImageGenerationCallPartialImage` event
2. Store base64 data and index (each overwrites previous)
3. Set completion flag on `ResponseImageGenerationCallCompleted`
4. Add last partial as DataPart only after completion

### Example Usage

#### Web Search

```dart
await for (final chunk in agent.sendStream('What are the latest Dart news?')) {
  final webSearchEvents = chunk.metadata['web_search'] as List?;
  if (webSearchEvents != null) {
    for (final event in webSearchEvents) {
      print('Stage: ${event['type']}');
    }
  }
}
```

#### Image Generation with Previews

```dart
await for (final chunk in agent.sendStream('Generate a logo')) {
  final imageEvents = chunk.metadata['image_generation'] as List?;
  if (imageEvents != null) {
    for (final event in imageEvents) {
      // Save partial images
      if (event['partial_image_b64'] != null) {
        final bytes = base64Decode(event['partial_image_b64']);
        savePreview(bytes, event['partial_image_index']);
      }
    }
  }

  // Final image as DataPart
  for (final msg in chunk.messages) {
    for (final part in msg.parts) {
      if (part is DataPart && part.mimeType.startsWith('image/')) {
        saveFinal(part.bytes);
      }
    }
  }
}
```

#### Code Interpreter

Code execution follows the same pattern as thinking/reasoning:
- **During streaming**: Individual code delta events stream in chunk metadata
- **After streaming**: Single accumulated code delta appears in message metadata

```dart
// Stream code as it's generated
await for (final chunk in agent.sendStream('Calculate fibonacci(100)')) {
  final codeEvents = chunk.metadata['code_interpreter'] as List?;
  if (codeEvents != null) {
    for (final event in codeEvents) {
      // Stream individual code deltas character-by-character if desired
      if (event['type'] == 'response.code_interpreter_call_code.delta') {
        stdout.write(event['delta']);
      }
    }
  }
}

// Access complete code in message metadata
final result = await agent.send('Calculate fibonacci(100)');
final codeEvents = agent.messages.last.metadata['code_interpreter'] as List?;
if (codeEvents != null) {
  // Find the accumulated code delta (single complete code block)
  final codeDelta = codeEvents.firstWhere(
    (e) => e['type'] == 'response.code_interpreter_call_code.delta',
    orElse: () => null,
  );
  if (codeDelta != null) {
    print('Complete code:\n${codeDelta['delta']}');
  }

  // Last event is synthetic summary with execution details
  final summary = codeEvents.last;
  print('Container: ${summary['container_id']}');
  print('Status: ${summary['status']}');

  // Container file citations include file_id and container_id for generated files
  final fileCitations = codeEvents.where((e) => e['type'] == 'container_file_citation').toList();
  for (final citation in fileCitations) {
    print('Generated file: ${citation['file_id']} in container ${citation['container_id']}');
  }
}

// Generated images are automatically attached as DataParts
final result = await agent.send('Create a plot and save it as plot.png');
for (final part in agent.messages.last.parts) {
  if (part is DataPart && part.mimeType.startsWith('image/')) {
    print('Image generated: ${part.bytes.length} bytes');
    // The image bytes are directly available in the message
  }
}
```

**File Generation**: When code interpreter generates files (e.g., via `plt.savefig()`), they are:
1. Referenced via `container_file_citation` annotations in the message metadata
2. Automatically downloaded and attached as `DataPart`s in the model's response
3. Citations with zero-length text ranges (start_index == end_index) are filtered out

## Testing Strategy

### Unit Tests

1. **Event recording**: Verify events are added to internal event log
2. **Metadata emission**: Check streaming chunks have events as single-item lists
3. **Final metadata**: Ensure complete event lists appear in message metadata
4. **Synthetic events**: Verify FileSearch/CodeInterpreter summaries are appended
5. **Image DataPart**: Confirm final image appears as DataPart when completed

### Integration Tests

1. **Web search flow**: Test full streaming + final metadata
2. **Image generation**: Test partial images + final DataPart
3. **File search**: Test streaming events + synthetic summary
4. **Code interpreter**: Test streaming + code/results in summary
5. **Multiple tools**: Test multiple server-side tools in one response

### Test Structure

Tests should verify:
- Streaming chunks contain single-item event lists for each tool event
- Final result contains complete accumulated event lists in message metadata
- Event types match expected progression for the provider
- Synthetic events are properly appended when tools have additional data
- Content deliverables appear as DataPart in message parts
- Result metadata does NOT contain tool events (only response-level metadata)

## Related Documentation

- [Message Handling Architecture](Message-Handling-Architecture.md) - Core message patterns
- [OpenAI Responses Provider Requirements](../plans/openai-responses-provider/responses-provider-requirements.md) - Feature requirements
- [OpenAI Responses Provider Technical Design](../plans/openai-responses-provider/responses-provider-tech-design.md) - Implementation details
- [State Management Architecture](State-Management-Architecture.md) - Session persistence patterns