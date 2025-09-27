# Welcome to Dartantic!

The [dartantic_ai](https://pub.dev/packages/dartantic_ai) package provides an
agent framework designed to make building client and server-side apps in Dart
with generative AI easier and more fun!

## Key Features

- **Agentic behavior with multi-step tool calling:** Let your AI agents
  autonomously chain tool calls together to solve multi-step problems without
  human intervention.
- **Multiple Providers Out of the Box** - OpenAI, OpenAI Responses, Google,
  Anthropic, Mistral, Cohere, Ollama, and more
- **Streaming Output** - Real-time response generation
- **Typed Outputs and Tool Calling** - Uses Dart types and JSON serialization
- **Multimedia Input** - Process text, images, and files
- **Embeddings** - Vector generation and semantic search
- **MCP Support** - Model Context Protocol server integration
- **Provider Switching** - Switch between AI providers mid-conversation
- **Production Ready**: Built-in logging, error handling, and retry handling
- **Extensible**: Easy to add custom providers as well as tools of your own or
  from your favorite MCP servers

## Quick Start

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart' show ChatMessage;
import 'package:json_schema/json_schema.dart' show JsonSchema;

void main() async {
  // Create an agent with your preferred provider
  final agent = Agent(
    'openai',  // or 'google', 'anthropic', 'ollama', etc.
  );

  // Generate text
  final result = await agent.send(
    'Explain quantum computing in simple terms', 
    history: [ChatMessage.system('You are a helpful assistant.')],
  );
  print(result.output);

  // Use typed outputs
  final location = await agent.sendFor<TownAndCountry>(
    'The windy city in the US',
    outputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'town': {'type': 'string'},
        'country': {'type': 'string'},
      },
      'required': ['town', 'country'],
    }),
    outputFromJson: TownAndCountry.fromJson,
  );
  print('${location.output.town}, ${location.output.country}');
}
```

## Documentation

**[Read the full documentation at
docs.dartantic.ai](https://docs.dartantic.ai)**

The documentation includes:
- **Getting Started Guide** - Installation and basic usage
- **Core Features** - JSON output, typed responses, and streaming
- **Advanced Features** - Tool calling, agentic behavior, and embeddings
- **Integration** - Logging, MCP servers, and custom providers
- **Provider Reference** - Detailed info on all supported providers
- **Examples** - Complete working examples for every feature

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dartantic_ai: ^VERSION
  dartantic_interface: ^VERSION
```

## Contributing & Community

Welcome contributions! Feature requests, bug reports and PRs are welcome on [the
dartantic_ai github site](https://github.com/csells/dartantic_ai).

Want to chat about Dartantic? Drop by [the Discussions
forum](https://github.com/davidmigloz/csells/dartantic_ai).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file
for details.

---

**Built with ❤️ for the Dart & Flutter community**
