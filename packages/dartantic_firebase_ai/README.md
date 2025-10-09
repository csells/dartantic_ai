# dartantic_firebase_ai

Firebase AI provider for [dartantic_ai](https://pub.dev/packages/dartantic_ai).

Provides access to Google's Gemini models through Firebase with enhanced security features including App Check, Firebase Authentication, and hybrid on-device inference support.

## Features

- 🔥 **Firebase Integration** - Seamless integration with Firebase services
- 🔒 **Enhanced Security** - App Check and Firebase Auth support
- 💻 **Hybrid Inference** - Cloud and on-device model support
- 🎯 **Full Gemini Capabilities** - Chat, function calling, structured output, vision
- 🚀 **Streaming Responses** - Real-time token generation
- 🛠️ **Tool Calling** - Function execution during generation

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

## Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)

2. Follow the [Firebase Flutter setup guide](https://firebase.google.com/docs/flutter/setup) for your platform

3. Enable Firebase AI Logic in your Firebase console

4. (Optional) Set up [App Check](https://firebase.google.com/docs/app-check) for enhanced security

## Usage

### Basic Chat

```dart
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';

// Initialize Firebase
await Firebase.initializeApp();

// Register the Firebase AI provider
Providers.providerMap['firebase'] = FirebaseAIProvider();

// Create an agent
final agent = Agent('firebase');

// Send a message
final result = await agent.send('Explain quantum computing in simple terms');
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

## Comparison to Google Provider

| Feature | Google Provider | Firebase AI Provider |
|---------|----------------|---------------------|
| API Access | Direct Gemini API | Through Firebase |
| Security | API key only | App Check + Auth |
| Platforms | All Dart | Flutter only |
| On-Device | No | Yes (preview) |
| Cost Control | Manual | Firebase quotas |

## Contributing

Contributions welcome! See the [contributing guide](https://github.com/csells/dartantic_ai/blob/main/CONTRIBUTING.md).

## License

MIT License - see [LICENSE](https://github.com/csells/dartantic_ai/blob/main/LICENSE)
