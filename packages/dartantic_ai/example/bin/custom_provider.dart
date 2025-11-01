// ignore_for_file: avoid_print

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';
import 'package:json_schema/json_schema.dart';

/// An example of how to add and use a custom provider.
void main() async {
  print('Adding the "echo" provider');
  Providers.providerMap['echo'] = EchoProvider();

  print('Using the echo provider');
  final agent = Agent('echo');
  const prompt = 'Hello, world!';
  final result = await agent.send(prompt);

  print('Prompt: "$prompt"');
  print('Response: "${result.output}"');
  print('');
  dumpMessages(result.messages);
  print('');
  print('Successfully echoed the prompt!');

  // Example: Getting a provider by name using Providers.get()
  print('\n═══ Getting providers by name ═══');

  // Get a built-in provider
  final openaiProvider = Providers.get('openai');
  print('Got provider: ${openaiProvider.displayName}');

  // Create an agent using the provider directly
  final openaiAgent = Agent.forProvider(
    openaiProvider,
    chatModelName: 'gpt-4o-mini',
  );
  print('Created agent with model: ${openaiAgent.model}');

  // Get our custom provider
  final echoProvider = Providers.get('echo');
  print('Got custom provider: ${echoProvider.displayName}');

  // You can also use aliases
  final googleProvider = Providers.get('gemini'); // alias for 'google'
  print('Got provider using alias: ${googleProvider.displayName}');
}

/// A mock model that echos back the prompt.
class EchoChatModel extends ChatModel<ChatModelOptions> {
  EchoChatModel({required super.name, ChatModelOptions? defaultOptions})
    : super(defaultOptions: defaultOptions ?? const ChatModelOptions());

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    ChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    assert(messages.isNotEmpty);
    assert(messages.last.role == ChatMessageRole.user);
    return Stream.fromIterable([
      ChatResult<ChatMessage>(
        output: ChatMessage.fromJson(
          messages.last.toJson()..['role'] = 'model',
        ),
      ),
    ]);
  }

  @override
  void dispose() {}

  @override
  String get name => 'echo';
}

/// A chat provider that provides an [EchoChatModel].
class EchoProvider
    extends
        Provider<
          ChatModelOptions,
          EmbeddingsModelOptions,
          MediaGenerationModelOptions
        > {
  EchoProvider()
    : super(
        name: 'echo',
        displayName: 'Echo',
        defaultModelNames: {ModelKind.chat: 'echo'},
        caps: {ProviderCaps.chat},
      );

  @override
  String get name => 'echo';

  @override
  Set<ProviderCaps> get caps => {ProviderCaps.chat};

  @override
  Stream<ModelInfo> listModels() => Stream.fromIterable([
    ModelInfo(
      name: 'echo',
      providerName: 'echo',
      kinds: const {ModelKind.chat},
    ),
  ]);

  @override
  ChatModel<ChatModelOptions> createChatModel({
    String? name,
    List<Tool<Object>>? tools,
    double? temperature,
    bool enableThinking = false,
    ChatModelOptions? options,
  }) => EchoChatModel(
    name: name ?? defaultModelNames[ModelKind.chat]!,
    defaultOptions: options,
  );

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw Exception('no support for embeddings models in this provider');

  @override
  MediaGenerationModel<MediaGenerationModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    MediaGenerationModelOptions? options,
  }) => throw UnsupportedError(
    'no support for media generation in this provider',
  );
}
