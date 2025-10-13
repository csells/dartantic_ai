## 1.2.0

- Migrated Google provider from deprecated `google_generative_ai` to generated
  `google_cloud_ai_generativelanguage_v1` package. This is an internal
  implementation change with no API surface changes for users. The migration
  includes:
  - New dependency on `google_cloud_ai_generativelanguage_v1` and related
    packages
  - Removed deprecated `google_generative_ai` dependency
  - All existing Google provider functionality preserved
- Internal chat orchestration rearchitecture to simplify Agent and chat model
  implementations and to focus per-provider orchestration on individual
  providers.
  - Added Anthropic orchestration provider to handle the toolcall-based
    method of typed output it requires.
  - Added Google double agent orchestrator to support typed output with
    tools simultaneously. Google's API doesn't support tools and `outputSchema`
    in a single call, so the orchestrator transparently executes a two-phase
    workflow: Phase 1 executes tools, Phase 2 requests structured output. This
    makes Google functionally equivalent to OpenAI and Anthropic for typed
    output + tools use cases.
- Used the updated openai_core package to refactor OpenAIResponsesChatModel to
  eliminate workaround for retrieving container file names. 

## 1.1.0

This is a big release!
- Added the OpenAI Responses provider built on `openai_core`, including session
  persistence (aka prompt caching), intrinsic server-side tools, and thinking
  metadata streams. Thanks to @jezell for his most excellent `openai_core`
  package and his quick turn-around on my blocking issues!
  - Streaming thinking and server-side tool call progress
  - Server-side image generation with quality, size and partial progress as well
    as generated image returned as part for ease of access
  - Server-side web search with full progress reports
  - Server-side code interpreter with reusable containers and returning of
    generated files of all types as parts for ease of access
  - Full server-side vector search tool with example showing how to upload files
    and query vectors
  - GPT-5 Codex access!
- Replaced the Lambda provider with the new `openai_compat.dart` sample
- Filtered Cohere models to "Live" entries and updated the default chat model
- Surface usage totals for every provider consistently
- Added support for the `DARTANTIC_LOG_LEVEL` environment variable for one-line
  logging configuration
- Support for the fully
  [spec](https://google.github.io/dotprompt/implementors/)-compliant
  [dotprompt_dart package](https://pub.dev/packages/dotprompt_dart)
- Published all of the specs for dartantic in a new Specifications section in
  the docs
- 1300+ tests to ensure feature compatibility across the set of supported LLMs

## 1.0.8

- fix a intermittent anthropic tool-calling error with streaming responses
- fix an openai-based tool-calling error that resulted in an infinite loop from
  empty responses after tool calls

## 1.0.7

- move from soti_schema to soti_schema_plus in examples, as the former seems to
  have been abandoned
- fixed: can't move to the latest version of freezed etc due to deps in
  ollama_dart [#54](https://github.com/csells/dartantic_ai/issues/54)
- fixed: apiKey and baseUrl parameters should be exposed from the OllamaProvider
  [#52](https://github.com/csells/dartantic_ai/issues/52)
- fixed: Dartantic AI package local dependency
  [#53](https://github.com/csells/dartantic_ai/issues/53)
- fixed: update for openai_dart 0.5.4
  [#51](https://github.com/csells/dartantic_ai/issues/51)
- fixed chatarang to use new streaming message collection pattern

## 1.0.6

- Fixed #48: Pass package name and other info to Generative AI providers. I
  added an example of how to use a custom HTTP client for these kinds of things
  when creating a model. It's not as easy as it could be, and it didn't work for
  gemini w/o a quick fix, but it's doable.

## 1.0.5

-  Fixed #47: Dartantic is checking for wrong environment variable. I was being
   aggressive about constructing providers before they were used and checking
   API keys before they were needed, which was causing this issue. For example,
   if you wanted to use `Agent('google')` and didn't have the MISTRAL_API_KEY
   set (why would you?), string lookup creates all of the providers, which caused
   all of them to check for their API key and -- BOOM.

## 1.0.4

- Updated LLM SDK dependencies:
  - `anthropic_sdk_dart`: 0.2.1 → 0.2.2
  - `openai_dart`: 0.5.2 → 0.5.3 (adds nullable choices field support for Groq compatibility)
  - `mistralai_dart`: 0.0.4 → 0.0.5
  - `ollama_dart`: 0.2.3 → 0.2.4

## 1.0.3

- Fixed quickstart example code and updated README

## 1.0.2

- fixed a compilation error on the web

## 1.0.1

- updating to dartantic_interface 1.0.1 (that didn't take long : )

## 1.0.0

### Dynamic => Static Provider instances

Provider instances are now static, so you can use the `Providers` class to get
them by name or alias:

```dart
// OLD
final provider = OpenAiProvider();
final providerFactory = Agent.providers['google'];
final providerFactoryByAlias = Agent.providers['gemini'];

// NEW
final provider1 = Providers.openai;
final provider2 = Providers.get('google');
final provider3 = Providers.get('gemini');
```

If you'd like to extend the list of providers dynamically at runtime, you can
use the `providerMap` property of the `Providers` class:

```dart
Providers.providerMap['my-provider'] = MyProvider();
```

### Agent.runXxx => Agent.sendXxx

The `Agent.runXxx` methods have been renamed for consistency with chat models
and the new `Chat` class:

```dart
// OLD
final result = await agent.run('Hello');
final typedResult = await agent.runFor<T>('Hello', outputSchema: schema);
await for (final chunk in agent.runStream('Hello')) {...}

// NEW
final result = await agent.send('Hello');
final typedResult = await agent.sendFor<T>('Hello', outputSchema: schema);
await for (final chunk in agent.sendStream('Hello')) {...}
```

Also, when you're sending a prompt to the agent, instead of passing a list of
messages via the messages parameter, you can pass it via the history parameter:

```dart
// OLD
final result = await agent.run('Hello', messages: messages);

// NEW
final result = await agent.send('Hello', history: history);
```

The subtle difference is that the history is a list of previous messages before
the prompt + optional attachments, which forms the new message. Love it or
don't, but it made sense to me at the time...

### Agent.provider => Agent.forProvider

The `Agent.provider` constructor has been renamed to `Agent.forProvider` for
clarity:

```dart
// OLD
final agent = Agent.provider(OpenAiProvider());

// NEW
final agent = Agent.forProvider(Providers.anthropic);
```

### Message => ChatMessage

The `Message` type has been renamed to `ChatMessage` for consistency with chat
models:

```dart
// OLD
var messages = <Message>[];
final response = await agent.run('Hello', messages: messages);
messages = response.messages.toList();

// NEW
var history = <ChatMessage>[];
final response = await agent.send('Hello', history: history);
history.addAll(response.messages);
```

### toSchema => JsonSchema.create

The `toSchema` method has been dropped in favor of the built-in
`JsonSchema.create` method for simplicity:

```dart
// OLD
final schema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'town': {'type': 'string'},
    'country': {'type': 'string'},
  },
  'required': ['town', 'country'],
}.toSchema();

// NEW
final schema = JsonSchema.create({
  'type': 'object',
  'properties': {
    'town': {'type': 'string', 'description': 'Name of the town'},
    'country': {'type': 'string', 'description': 'Name of the country'},
  },
  'required': ['town', 'country'],
});
```

### systemPrompt + Message.system() => ChatMessage.system()

The `systemPrompt` parameter has been removed from Agent and model constructors.
It was confusing to have both a system prompt and a system message, so I've
simplified the implementation to use just an optional `ChatMessage.system()`
instead. In practice, you'll want to keep the system message in the history
anyway, so think of this as a "pit of success" thing:

```dart
// OLD
final agent = Agent(
  'openai',
  systemPrompt: 'You are a helpful assistant.',
);
final result = await agent.send('Hello');

// NEW
final agent = Agent('openai');
final result = await agent.send(
  'Hello',
  history: [
    const ChatMessage.system('You are a helpful assistant.'),
  ],
);
```

### Agent chat and streaming

The agent now streams new messages as they're created along with the output:

```dart
final agent = Agent('openai');
final history = <ChatMessage>[];
await for (final chunk in agent.sendStream('Hello', history: history)) {
  // collect text and messages as they're created
  print(chunk.output);
  history.addAll(chunk.messages);
}
```

If you'd prefer not to collect and track the message history manually, you can
use the `Chat` class to collect messages for you:

```dart
final chat = Chat(Agent('openai'));
await for (final chunk in chat.sendStream('Hello')) {
  print(chunk.output);
}

// chat.history is a list of ChatMessage objects
```

### DataPart.file(File) => DataPart.fromFile(XFile)

The `DataPart.file` constructor has been replaced with `DataPart.fromFile` to
support cross-platform file handling, i.e. the web:

```dart
// OLD
import 'dart:io';

final part = await DataPart.file(File('bio.txt'));

// NEW
import 'package:cross_file/cross_file.dart';

final file = XFile.fromData(
  await File('bio.txt').readAsBytes(), 
  path: 'bio.txt',
);
final part = await DataPart.fromFile(file);
```

### Model String Format Enhanced

The model string format has been enhanced to support chat, embeddings and other
model names using custom relative URI. This was important to be able to specify
the model for chat and embeddings separately:

```dart
// OLD
Agent('openai');
Agent('openai:gpt-4o');
Agent('openai/gpt-4o');

// NEW - all of the above still work plus:
Agent('openai?chat=gpt-4o&embeddings=text-embedding-3-large');
```

### Agent.embedXxx

The agent gets new `Agent.embedXxx` methods for creating embeddings for
documents and queries:

```dart
final agent = Agent('openai');
final embedding = await agent.embedQuery('Hello world');
final results = await agent.embedDocuments(['Text 1', 'Text 2']);
final similarity = EmbeddingsModel.cosineSimilarity(e1, e2);
```

Also, the `cosineSimilarity` method has been moved to the `EmbeddingsModel`.

### Automatic Retry

The agent now supports automatic retry for rate limits and failures:

```dart
final agent = Agent('openai');
final result = await agent.send('Hello!'); // Automatically retries on 429
```

### Agent&lt;TOutput&gt;(outputSchema) => sendForXxx&lt;TOutput&gt;(outputSchema)

Instead of putting the output schema on the `Agent` class, it's now on the
`sendForXxx` method:

```dart
// OLD
final agent = Agent<Map<String, dynamic>>('openai', outputSchema: ...);
final result = await agent.send('Hello');

// NEW
final agent = Agent('openai');
final result = await agent.sendFor<Map<String, dynamic>>('Hello', outputSchema: ...);
```

This allows you to be more flexible from message to message.

### `AgentResponse` to `ChatResult<MyType>`

The `AgentResponse` type has been renamed to `ChatResult`.

### DotPrompt Support Removed

The dependency on [the dotprompt_dart
package](https://pub.dev/packages/dotprompt_dart) has been removed from
dartantic_ai. However, you can still use the `DotPrompt` class to parse
`.prompt` files:

```dart
import 'package:dotprompt_dart/dotprompt_dart.dart';

final dotPrompt = DotPrompt(...);
final prompt = dotPrompt.render();
final agent = Agent(dotPrompt.frontMatter.model!);
await agent.send(prompt);
```

### Tool Calls with Typed Output

The `Agent.sendForXxx` method now supports specifying the output type of the
tool call:

```dart
final provider = Providers.openai;
assert(provider.caps.contains(ProviderCaps.typedOutputWithTools));

// tools
final agent = Agent.forProvider(
  provider,
  tools: [currentDateTimeTool, temperatureTool, recipeLookupTool],
);

// typed output
final result = await agent.sendFor<TimeAndTemperature>(
  'What is the time and temperature in Portland, OR?',
  outputSchema: TimeAndTemperature.schema,
  outputFromJson: TimeAndTemperature.fromJson,
);

// magic!
print('time: ${result.output.time}');
print('temperature: ${result.output.temperature}');
```

Unfortunately, not all providers support this feature. You can check the
provider's capabilities to see if it does.

### ChatMessage Part Helpers

The `ChatMessage` class has been enhanced with helpers for extracting specific
types of parts from a list:

```dart
final message = ChatMessage.system('You are a helpful assistant.');
final text = message.text; // "You are a helpful assistant."
final toolCalls = message.toolCalls; // []
final toolResults = message.toolResults; // []
```

### Usage Tracking

The agent now supports usage tracking:

```dart
final result = await agent.send('Hello');
print('Tokens used: ${result.usage.totalTokens}');
```

### Logging

The agent now supports logging:

```dart
Agent.loggingOptions = const LoggingOptions(level: LogLevel.ALL);
```

## 0.9.7

- Added the ability to set embedding dimensionality
- Removed ToolCallingMode and singleStep mode. Multi-step tool calling is now
  always enabled.
- Enabled support for web and wasm.
- Breaking Change: Replaced `DataPart.file` with `DataPart.stream` for file and
  image attachments. This improves web and WASM compatibility. Use
  `DataPart.stream(file.openRead(), name: file.path)` instead of
  `DataPart.file(File(...))`.

## 0.9.6

- fixed an issue where the OpenAI model only processed the last tool result when
  multiple tool results existed in a single message, causing unmatched tool call
  IDs during provider switching.

## 0.9.5

- Major OpenAI Multi-Step Tool Calling Improvement: Eliminated complex probe
  mechanism (100+ lines of code) in favor of [OpenAI's native
  `parallelToolCalls`
  parameter](https://pub.dev/documentation/openai_dart/latest/openai_dart/CreateChatCompletionRequest/parallelToolCalls.html).
  This dramatically simplifies the implementation while improving reliability
  and performance.

## 0.9.4

- README & docs tweaks

## 0.9.3

- Completely revamped docs! https://docs.page/csells/dartantic_ai

## 0.9.2

- Added `Agent.environment` to allow setting environment variables
  programmatically. This is especially useful for web applications where
  traditional environment variables are not available.

## 0.9.1

- Added support for extending the provider table at runtime, allowing custom
  providers to be registered dynamically.

- Added optional `name` parameter to `DataPart` and `LinkPart` for better
  multi-media message creation ergonomics.

## 0.9.0

- Added `ToolCallingMode` to control multi-step tool calling behavior.
  - `multiStep` (default): The agent will continue to send tool results until
    all of the tool calls have been exercised.
  - `singleStep`: The agent will perform only one request-response and then
    stop.

- OpenAI Multi-Step Tool Calling by including probing for additional tool calls
  when the model responds with text instead of a tool call.

- Gemini multi-step tool calling by handling new tool calls while processing the
  response from previous tool calling.

- Schema Nullable Properties Fix: Required properties in JSON schemas now
  correctly set `nullable: false` in converted Gemini schemas, since required
  properties cannot be null by definition.

## 0.8.3

- Breaking Change: `McpServer` → `McpClient`: Renamed MCP integration class cuz
  we're not building a server!
- MCP Required Fields Preservation: Enhanced MCP integration to preserve
  required fields in tool schemas, allowing LLMs to know what parameters are
  required for each tool call. This turns out to be a critical piece in whether
  the LLM is able to call the tool correctly or not.
- Model discovery: Added `Provider.listModels()` to enumerate available models,
  and the kinds of operations they support and whether they're in stable or
  preview/experimental mode.
- Breaking Change: simplifying provider names (again!)
- no change to actual provider aliases, e.g. "gemini" still maps to "google"
- fixed a nasty fully-qualified model naming bug
- Better docs!

## 0.8.2

- Better docs!

## 0.8.1

- Breaking change: Content=>List<Part>, lots more List<> => Iterable<>

## 0.8.0

- Multimedia Input Support: Added `attachments` parameter to Agent and Model
  interfaces for including files, data and links.
- Improved OpenAI compatibility for tool calls
- Added the 'gemini-compat' provider for access to Gemini models via the OpenAI
  endpoint.
- Breaking change: everywhere I passed List<Message> I now pass
  Iterable<Message>

## 0.7.0

- Provider Capabilities System: Add support for providers to declare their
  capabilities
- baseUrl support to enable OpenAI-compatibility
- Added new "openrouter" provider
  - it's an OpenAI API implementation, but doesn't support embeddings
  - which drove support for provider capabilities...
- temperature support
- Breaking change: `McpServer.remote` now takes a `Uri` instead of a `String`
  for the URL
- Breaking change: Renamed model interface properties for clarity:
  - `Model.modelName` → `Model.generativeModelName`
  - Also added `Model.embeddingModelName`
- Breaking change: Provider capabilities API naming:
  - `Provider.caps` returns `Set<ProviderCaps>` instead of
    `Iterable<ProviderCaps>`

## 0.6.0

- MCP (Model Context Protocol) Server Support
- Message construction convenience methods:
  - Added `Content` type alias for `List<Part>` to improve readability
  - Added convenience constructors for `Message`: `Message.system()`,
    `Message.user()`, `Message.model()`
  - Added `Content.text()` extension method for easy text content creation
  - Added convenience constructors for `ToolPart`: `ToolPart.call()` and
    `ToolPart.result()`
- Breaking change: inputType/outputType to inputSchema/outputSchema; I couldn't
  stand to look at `inputType` and `outputType` in the code anymore!
- Add logging support (defaults to off) and a logging example

## 0.5.0

- Embedding generation: Add methods to generate vector embeddings for text

## 0.4.0

- Streaming responses via `Agent.runStream` and related methods.
- Multi-turn chat support
- Provider switching: seamlessly alternate between multiple providers in a
  single conversation, with full context and tool call/result compatibility.

## 0.3.0

- added [dotprompt_dart](https://pub.dev/packages/dotprompt_dart) package
  support via `Agent.runPrompt(DotPrompt prompt)`
- expanded model naming to include "providerName", "providerName:model" or
  "providerName/model", e.g. "openai" or "googleai/gemini-2.0-flash"
- move types specified by `Map<String, dynamic>` to a `JsonSchema` object; added
  `toMap()` extension method to `JsonSchema` and `toSchema` to `Map<String,
  dynamic>` to make going back and forth more convenient.
- move the provider argument to `Agent.provider` as the most flexible case, but
  also the less common one. `Agent()` will contine to take a model string.

## 0.2.0

- Define tools and their inputs/outputs easily
- Automatically generate LLM-specific tool/output schemas
- Allow for a model descriptor string that just contains a family name so that
  the provider can choose the default model.

## 0.1.0

- Multi-Model Support (just Gemini and OpenAI models so far)
- Create agents from model strings (e.g. `openai:gpt-4o`) or typed providers
  (e.g. `GoogleProvider()`)
- Automatically check environment for API key if none is provided (not web
  compatible)
- String output via `Agent.run`
- Typed output via `Agent.runFor`

## 0.0.1

- Initial version.
