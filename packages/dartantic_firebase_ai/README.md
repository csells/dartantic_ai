# dartantic_firebase_ai

Firebase AI provider for [dartantic_ai](https://pub.dev/packages/dartantic_ai).

Provides access to Google's Gemini models through Firebase with flexible backend options for both development and production use.

## Features

- 🔥 **Dual Backend Support** - Google AI (development) and Vertex AI (production)
- 🔒 **Enhanced Security** - App Check and Firebase Auth support (Vertex AI)
- 🎯 **Full Gemini Capabilities** - Chat, function calling, structured output, vision
- 🚀 **Streaming Responses** - Real-time token generation
- 🛠️ **Tool Calling** - Function execution during generation
- 🔄 **Easy Migration** - Switch backends without code changes

## Platform Support

- ✅ iOS
- ✅ Android
- ✅ macOS
- ✅ Web

**Note:** This is a Flutter-specific package and requires the Flutter SDK.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dartantic_interface: ^1.0.3
  dartantic_firebase_ai: ^0.1.0
  firebase_core: ^3.12.0
```

## Backend Setup Requirements

### Google AI Backend (Development)
- **No Firebase project required** for basic usage
- Only needs Google AI API key 
- Direct access to Gemini Developer API
- Simpler setup for prototyping and development

### Vertex AI Backend (Production)
- **Requires Firebase project** with Google Cloud billing enabled
- Full Firebase integration with security features
- Follow the [Firebase Flutter setup guide](https://firebase.google.com/docs/flutter/setup) for your platform
- Enable Firebase AI Logic in your Firebase console
- (Optional) Set up [App Check](https://firebase.google.com/docs/app-check) for enhanced security

## Usage

### Backend Selection

Firebase AI supports two backends with different setup requirements:

**Google AI Backend** (for development/testing):
- Uses Gemini Developer API directly
- No Firebase project needed - just an API key
- Good for prototyping and development

**Vertex AI Backend** (for production):
- Requires complete Firebase project setup
- Full Firebase integration with security features
- App Check, Firebase Auth support
- Production-ready infrastructure

### Basic Setup

```dart
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';

// Initialize Firebase (required for both backends)
await Firebase.initializeApp();

// Option 1: Vertex AI (production-ready, requires Firebase project)
Providers.providerMap['firebase-vertex'] = FirebaseAIProvider();

// Option 2: Google AI (development, minimal Firebase setup)
Providers.providerMap['firebase-google'] = FirebaseAIProvider(
  backend: FirebaseAIBackend.googleAI,
);

// Create agents
final prodAgent = Agent('firebase-vertex:gemini-2.0-flash');
final devAgent = Agent('firebase-google:gemini-2.0-flash');

// Send a message
final result = await prodAgent.send('Explain quantum computing');
print(result.output);
```

### With Streaming

```dart
await for (final chunk in agent.stream('Tell me a story')) {
  print(chunk.output);
}
```

### With Tools

```dart
final weatherTool = Tool(
  name: 'get_weather',
  description: 'Get current weather for a location',
  inputSchema: JsonSchema.create({
    'type': 'object',
    'properties': {
      'location': {'type': 'string'},
    },
    'required': ['location'],
  }),
  function: (args) async {
    // Your weather API call here
    return {'temp': 72, 'condition': 'sunny'};
  },
);

final agent = Agent.forProvider(
  FirebaseAIProvider(),
  tools: [weatherTool],
);

final result = await agent.send('What\'s the weather in San Francisco?');
```

### Hybrid On-Device Inference

```dart
final agent = Agent.forProvider(
  FirebaseAIProvider(),
  options: FirebaseAIChatOptions(
    inferenceMode: InferenceMode.preferOnDevice, // Local first, cloud fallback
  ),
);
```

## Configuration Options

The `FirebaseAIChatOptions` class supports:

- `temperature` - Sampling temperature (0.0 to 1.0)
- `topP` - Nucleus sampling threshold
- `topK` - Top-K sampling
- `maxOutputTokens` - Maximum tokens to generate
- `stopSequences` - Stop generation sequences
- `safetySettings` - Content safety configuration
- `inferenceMode` - Hybrid inference mode (preview)

## Security Best Practices

1. **Use App Check** to prevent unauthorized API usage
2. **Enable Firebase Auth** for user-based access control
3. **Set up Firebase Security Rules** to protect your data
4. **Monitor usage** in Firebase console to detect anomalies

## Dependencies and Requirements

**This package requires Flutter** - it cannot be used in pure Dart projects due to:
- Flutter-specific Firebase SDK dependencies (`firebase_core`, `firebase_auth`, etc.)
- Platform-specific Firebase initialization code
- Flutter framework dependencies for UI integrations

For pure Dart projects, consider using the `dartantic_google` provider instead.

## Comparison to Google Provider

| Feature | Google Provider | Firebase AI Provider |
|---------|----------------|---------------------|
| API Access | Direct Gemini API | Through Firebase |
| Setup | API key only | Firebase project + API key |
| Security | API key only | App Check + Auth |
| Platforms | All Dart platforms | Flutter only |
| On-Device | No | Yes (preview) |
| Cost Control | Manual | Firebase quotas |
| Dependencies | HTTP client only | Full Firebase SDK |

## Contributing

Contributions welcome! See the [contributing guide](https://github.com/csells/dartantic_ai/blob/main/CONTRIBUTING.md).

## License

MIT License - see [LICENSE](https://github.com/csells/dartantic_ai/blob/main/LICENSE)
