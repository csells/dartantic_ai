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
- **OpenAI-Compatibility** - Access to literally thousands of providers via the
  OpenAI API that nearly every single modern LLM provider implements
- **Streaming Output** - Real-time response generation
- **Typed Outputs and Tool Calling** - Uses Dart types and JSON serialization
- **Multimedia Input** - Process text, images, and files
- **Media Generation** - Stream images, PDFs, and other artifacts from OpenAI
  Responses, Google Gemini (Nana Banana), and Anthropic code execution
- **Embeddings** - Vector generation and semantic search
- **Model Reasoning ("Thinking")** - Extended reasoning support across OpenAI
  Responses, Anthropic, and Google
- **Provider-Hosted Server-Side Tools** - Web search, file search, image
  generation, and code interpreter via OpenAI Responses, Anthropic, and Google
- **MCP Support** - Model Context Protocol server integration
- **Provider Switching** - Switch between AI providers mid-conversation
- **Production Ready**: Built-in logging, error handling, and retry handling
- **Extensible**: Easy to add custom providers as well as tools of your own or
  from your favorite MCP servers

## Quick Start

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart' show JsonSchema;

void main() async {
  // Create an agent with your preferred provider
  final agent = Agent(
    'openai',  // or 'openai-responses', 'google', 'anthropic', etc.
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

## Contributing & Community

Welcome contributions! Feature requests, bug reports and PRs are welcome on [the
dartantic_ai github site](https://github.com/csells/dartantic_ai).

Want to chat about Dartantic? Drop by [the Discussions
forum](https://github.com/csells/dartantic_ai/discussions).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file
for details.

---

**Built with ❤️ for the Dart & Flutter community**
