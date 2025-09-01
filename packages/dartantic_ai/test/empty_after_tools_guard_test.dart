import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

class DummyProvider extends Provider<ChatModelOptions, EmbeddingsModelOptions> {
  DummyProvider()
    : super(
        name: 'dummy',
        displayName: 'Dummy',
        defaultModelNames: const {ModelKind.chat: 'test-model'},
        caps: const {ProviderCaps.chat},
      );

  DummyChatModel? lastModel;

  @override
  ChatModel<ChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    ChatModelOptions? options,
  }) {
    lastModel = DummyChatModel(
      name: name ?? defaultModelNames[ModelKind.chat]!,
      tools: tools,
      temperature: temperature,
    );
    return lastModel!;
  }

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw UnsupportedError('Embeddings not supported in DummyProvider');

  @override
  Stream<ModelInfo> listModels() async* {}
}

class DummyChatModel extends ChatModel<ChatModelOptions> {
  DummyChatModel({required super.name, super.tools, super.temperature})
    : super(defaultOptions: const ChatModelOptions());

  int sendCalls = 0;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    ChatModelOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    sendCalls++;

    // Stage 1: No tool results yet -> issue a single tool call
    final hasToolResults = messages.any(
      (m) => m.parts.whereType<ToolPart>().any(
        (p) => p.kind == ToolPartKind.result,
      ),
    );

    if (!hasToolResults) {
      const toolCall = ToolPart.call(
        id: 'call_1',
        name: 'write_file',
        arguments: {'path': 'lib/x.dart', 'content': 'hello'},
      );
      const msg = ChatMessage(role: ChatMessageRole.model, parts: [toolCall]);
      yield ChatResult<ChatMessage>(
        output: msg,
        messages: const [msg],
        finishReason: FinishReason.toolCalls,
        metadata: const {},
        usage: const LanguageModelUsage(),
      );
      return;
    }

    // Stage 2+: After tool results, return an empty assistant message
    const empty = ChatMessage(role: ChatMessageRole.model, parts: []);
    yield ChatResult<ChatMessage>(
      output: empty,
      messages: const [ChatMessage(role: ChatMessageRole.model, parts: [])],
      finishReason: FinishReason.stop,
      metadata: const {},
      usage: const LanguageModelUsage(),
    );
  }

  @override
  void dispose() {}
}

// Wrapper around real providers to avoid network; returns in-memory model
class WrapperProvider
    extends Provider<ChatModelOptions, EmbeddingsModelOptions> {
  WrapperProvider(Provider base)
    : super(
        name: 'wrap-${base.name}',
        displayName: 'Wrapper(${base.displayName})',
        defaultModelNames: {
          ModelKind.chat: base.defaultModelNames[ModelKind.chat] ?? 'model',
        },
        caps: base.caps,
        aliases: base.aliases,
      );

  late DummyModel lastModel;

  @override
  ChatModel<ChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    ChatModelOptions? options,
  }) => lastModel = DummyModel(name: name ?? 'model');

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw UnsupportedError('Embeddings not supported in WrapperProvider');

  @override
  Stream<ModelInfo> listModels() async* {}
}

class DummyModel extends ChatModel<ChatModelOptions> {
  DummyModel({required super.name})
    : super(defaultOptions: const ChatModelOptions());

  int sendCalls = 0;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    ChatModelOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    sendCalls++;
    final hasToolResults = messages.any(
      (m) => m.parts.whereType<ToolPart>().any(
        (p) => p.kind == ToolPartKind.result,
      ),
    );

    if (!hasToolResults) {
      // Emit a single tool call on first pass
      const toolCall = ToolPart.call(
        id: 'call_1',
        name: 'write_file',
        arguments: {'path': 'lib/x.dart', 'content': 'hello'},
      );
      const msg = ChatMessage(role: ChatMessageRole.model, parts: [toolCall]);
      yield ChatResult<ChatMessage>(
        output: msg,
        messages: const [msg],
        finishReason: FinishReason.toolCalls,
        metadata: const {},
        usage: const LanguageModelUsage(),
      );
      return;
    }

    // After tool results, return an empty assistant message
    const empty = ChatMessage(role: ChatMessageRole.model, parts: []);
    yield ChatResult<ChatMessage>(
      output: empty,
      messages: const [empty],
      finishReason: FinishReason.stop,
      metadata: const {},
      usage: const LanguageModelUsage(),
    );
  }

  @override
  void dispose() {}
}

void main() {
  test('allows one empty-after-tools continuation then stops', () async {
    final provider = DummyProvider();

    final writeFile = Tool(
      name: 'write_file',
      description: 'Create or overwrite a file',
      inputSchema: JsonSchema.create({
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
        'required': ['path', 'content'],
      }),
      onCall: (args) async => {'ok': true},
    );

    final agent = Agent.forProvider(
      provider,
      chatModelName: 'test-model',
      tools: [writeFile],
    );

    final result = await agent.send('minimal');

    // Verify the model was invoked exactly 3 times:
    //  1) tool call, 2) first empty (continue), 3) second empty (stop)
    expect(provider.lastModel, isNotNull);
    expect(provider.lastModel!.sendCalls, equals(3));

    // Verify the final message is the empty assistant message
    expect(result.messages, isNotEmpty);
    final lastMsg = result.messages.last;
    expect(lastMsg.role, equals(ChatMessageRole.model));
    expect(lastMsg.parts, isEmpty);
  });

  group('Cross-provider behavior', () {
    test(
      'default orchestrator: continues once then stops for each provider',
      () async {
        final toolProviders = Providers.allWith({
          ProviderCaps.chat,
          ProviderCaps.multiToolCalls,
        });

        final writeFile = Tool(
          name: 'write_file',
          description: 'Create or overwrite a file',
          inputSchema: JsonSchema.create({
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
            },
            'required': ['path', 'content'],
          }),
          onCall: (args) async => {'ok': true},
        );

        for (final base in toolProviders) {
          final wrapper = WrapperProvider(base);
          final agent = Agent.forProvider(
            wrapper,
            chatModelName: base.defaultModelNames[ModelKind.chat],
            tools: [writeFile],
          );

          final result = await agent.send('minimal');

          // 1) tool call, 2) first empty (continue), 3) second empty (stop)
          expect(
            wrapper.lastModel.sendCalls,
            equals(3),
            reason: 'provider=${base.name}',
          );
          expect(result.messages, isNotEmpty, reason: 'provider=${base.name}');
          final lastMsg = result.messages.last;
          expect(
            lastMsg.role,
            equals(ChatMessageRole.model),
            reason: 'provider=${base.name}',
          );
          expect(lastMsg.parts, isEmpty, reason: 'provider=${base.name}');
        }
      },
    );

    test('typed-output orchestrator path does not loop', () async {
      final toolProviders = Providers.allWith({
        ProviderCaps.chat,
        ProviderCaps.multiToolCalls,
      });

      final writeFile = Tool(
        name: 'write_file',
        description: 'Create or overwrite a file',
        inputSchema: JsonSchema.create({
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'content': {'type': 'string'},
          },
          'required': ['path', 'content'],
        }),
        onCall: (args) async => {'ok': true},
      );

      final outputSchema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'ok': {'type': 'boolean'},
        },
        'required': ['ok'],
      });

      for (final base in toolProviders) {
        final wrapper = WrapperProvider(base);
        final agent = Agent.forProvider(
          wrapper,
          chatModelName: base.defaultModelNames[ModelKind.chat],
          tools: [writeFile],
        );

        final result = await agent.send('minimal', outputSchema: outputSchema);

        // Expect at least 2 sendStream calls and no unbounded growth
        expect(
          wrapper.lastModel.sendCalls >= 2,
          isTrue,
          reason: 'provider=${base.name}',
        );
        final lastMsg = result.messages.last;
        expect(
          lastMsg.role,
          equals(ChatMessageRole.model),
          reason: 'provider=${base.name}',
        );
        expect(lastMsg.parts, isEmpty, reason: 'provider=${base.name}');
      }
    });
  });
}
