# Custom Providers

Create your own providers and use them like the built-in providers. You can
choose to implement either a `ChatModel` or an `EmbeddingsModel` or both.

## Dependencies

You do not need to depend on the `dartantic_ai` package to create a custom
provider. The `dartantic_interface` package is all you need.

```yaml
dependencies:
  dartantic_interface: ^VERSION
```

## Creating a Custom Provider

Here's a simple example of a custom provider that exposes a `ChatModel`:

```dart
class EchoProvider extends Provider<
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
  ChatModel<ChatModelOptions> createChatModel({
    String? name,
    List<Tool<Object>>? tools,
    double? temperature,
    ChatModelOptions? options,
  }) => EchoChatModel(
    name: name ?? defaultModelNames[ModelKind.chat]!,
    defaultOptions: options,
  );
  
  @override
  MediaGenerationModel<MediaGenerationModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    MediaGenerationModelOptions? options,
  }) => throw UnsupportedError('Media generation is not supported.');

  // ... other required methods
}
```

## Custom Model

Here's a minimal chat model example:

```dart
class EchoChatModel extends ChatModel<ChatModelOptions> {
  EchoChatModel({required super.name, ChatModelOptions? defaultOptions})
    : super(defaultOptions: defaultOptions ?? const ChatModelOptions());

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    ChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    // Echo back the last user message
    return Stream.fromIterable([
      ChatResult<ChatMessage>(
        output: ChatMessage.fromJson(
          messages.last.toJson()..['role'] = 'model',
        ),
      ),
    ]);
  }
}
```

With your custom provider, you can use it with an agent:

```dart
final agent = Agent.forProvider(EchoProvider());
final result = await agent.send('Hello!');
print(result.output); // Echoes back your input
```

## Dynamic Provider Registration

If you'd like to participate in the named lookup of providers, you can add your
custom provider to the provider map:

```dart
// Add your custom provider to the registry
Provider.providerMap['echo'] = EchoProvider();

// Use it like any built-in provider
final agent = Agent('echo');
final result = await agent.send('Hello!');
print(result.output); // Echoes back your input
```

## Examples

- [Custom Provider](https://github.com/csells/dartantic_ai/blob/main/packages/dartantic_ai/example/bin/custom_provider.dart)
