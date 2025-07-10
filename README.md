# Welcome to Dartantic!

The [dartantic_ai](https://pub.dev/packages/dartantic_ai) package provides an
agent framework inspired by pydantic-ai and designed to make building client and
server-side apps in Dart with generative AI easier and more fun!

## Goals

- **Agentic behavior with multi-step tool calling:** Let your AI agents
  autonomously chain tool calls together to solve multi-step problems without
  human intervention.
- **Multi-Provider Support**: Works with OpenAI, Google Gemini, Anthropic Claude and more
- **Type Safety**: Leverage Dart's strong typing with automatic JSON schema
  generation
- **Production Ready**: Built-in logging, error handling, and provider
  capabilities detection
- **Extensible**: Easy to add custom providers and tools

## Quick Start

```dart
import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  // Create an agent with your preferred provider
  final agent = Agent(
    'openai',  // or 'claude', 'gemini', 'openrouter', etc.
    systemPrompt: 'You are a helpful assistant.',
  );

  // Generate text
  final result = await agent.run('Explain quantum computing in simple terms');
  print(result.output);

  // Use typed outputs
  final location = await agent.runFor<TownAndCountry>(
    'The windy city in the US',
    outputSchema: TownAndCountry.schemaMap.toSchema(),
    outputFromJson: TownAndCountry.fromJson,
  );
  print('${location.output.town}, ${location.output.country}');
}
```

## Key Features

- **Streaming Output** - Real-time response generation
- **Typed Tool Calling** - Type-safe function definitions and execution
- **Multi-media Input** - Process text, images, and files
- **Embeddings** - Vector generation and semantic search
- **MCP Support** - Model Context Protocol server integration
- **Provider Switching** - Switch between AI providers mid-conversation with the
  full stack of messages, including messages, media and tool calls

## Documentation

**[Read the full documentation](https://docs.page/csells/dartantic_ai)**

The documentation includes:
- **Getting Started Guide** - Installation and basic usage
- **Core Features** - JSON output, typed responses, and DotPrompt support
- **Advanced Features** - Tool calling, agentic behavior, streaming, and
  embeddings
- **Integration** - Logging, model discovery, MCP servers, and custom providers

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dartantic_ai: ^latest_version
```

## Contributing & Community

Welcome contributions! Feature requests, bug reports and PRs are welcome on [the
dartantic_ai github site](https://github.com/csells/dartantic_ai).

Want to chat about Dartantic? Then drop by [the Discussions
forum](https://github.com/csells/dartantic_ai/discussions/).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file
for details.

---

**Built with ❤️ for the Dart & Flutter community**
