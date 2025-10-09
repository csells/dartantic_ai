# Firebase AI Provider for dartantic_ai

A comprehensive Firebase AI provider that integrates Google's Gemini models through Firebase with the dartantic_ai framework.

## Features

### ✅ Core Capabilities
- **Chat Models**: Full support for Gemini 2.0 Flash, Gemini 1.5 Flash, and Gemini 1.5 Pro
- **Multi-modal Input**: Images, audio, video, and document support 
- **Tool Calling**: Function calling with Firebase AI's native tool support
- **Code Execution**: Built-in code execution capabilities via `enableCodeExecution`
- **Typed Output**: JSON schema-based structured output generation
- **Streaming**: Real-time response streaming with enhanced error handling
- **Vision**: Image analysis and visual question answering
- **Thinking Mode**: Reasoning process capture and analysis

### 🚀 Advanced Features  
- **Enhanced Error Handling**: Comprehensive error mapping and retry logic
- **Usage Tracking**: Detailed token counting and cost analytics
- **Safety Analysis**: Content filtering and safety rating analysis
- **Citation Metadata**: Source attribution and reference tracking
- **Streaming Accumulation**: Smart response accumulation across chunks
- **Multi-modal Validation**: File type and size validation for media inputs

## Quick Start

### 1. Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dartantic_ai: 
    git:
      url: https://github.com/csells/dartantic_ai.git
      ref: responses-api-package
      path: packages/dartantic_ai
  dartantic_firebase_ai:
    path: ../dartantic_firebase_ai
  firebase_ai: ^3.3.0
  firebase_core: ^3.6.0
```

### 2. Firebase Setup

Initialize Firebase in your app:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MyApp());
}
```

### 3. Basic Usage

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';

// Register the Firebase AI provider
void main() {
  Providers.providerMap['firebase'] = FirebaseAIProvider();
  
  // Use with Agent
  final agent = Agent('firebase:gemini-2.0-flash');
  final response = await agent.send('Hello, Firebase AI!');
  print(response);
}
```

## Comprehensive Examples

### Multi-modal Input

```dart
import 'dart:io';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';

Future<void> multiModalExample() async {
  final agent = Agent('firebase:gemini-2.0-flash');
  
  // Load an image
  final imageFile = File('path/to/image.jpg');
  final imageBytes = await imageFile.readAsBytes();
  
  // Validate media before sending
  final validation = FirebaseAIMultiModalUtils.validateMedia(
    bytes: imageBytes,
    mimeType: 'image/jpeg',
  );
  
  if (!validation.isValid) {
    print('Invalid image: ${validation.error}');
    return;
  }
  
  // Create optimized data part
  final imagePart = FirebaseAIMultiModalUtils.createOptimizedDataPart(
    bytes: imageBytes,
    mimeType: 'image/jpeg',
  );
  
  if (imagePart != null) {
    final message = ChatMessage(
      role: ChatMessageRole.user,
      parts: [
        TextPart('What do you see in this image?'),
        imagePart,
      ],
    );
    
    final response = await agent.send([message]);
    print('Vision Response: ${response}');
  }
}
```

### Thinking Mode

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';

Future<void> thinkingModeExample() async {
  final agent = Agent('firebase:gemini-2.0-flash');
  
  // Enable thinking mode options
  const thinkingOptions = FirebaseAIThinkingOptions(
    enabled: true,
    includeReasoningSteps: true,
    includeSafetyAnalysis: true,
    verboseCitationMetadata: true,
  );
  
  final response = await agent.send(
    'Explain the reasoning behind your answer: What is 2+2?'
  );
  
  // Extract thinking content
  final thinking = FirebaseAIThinkingUtils.extractThinking(
    response,
    options: thinkingOptions,
  );
  
  if (thinking != null) {
    print('🧠 Model Reasoning:');
    print(thinking);
    print('\n✅ Final Answer:');
  }
  
  print(response.output);
}
```

### Code Execution

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';

Future<void> codeExecutionExample() async {
  // Create model with code execution enabled
  final provider = FirebaseAIProvider();
  final model = provider.createChatModel(
    name: 'gemini-2.0-flash',
    options: const FirebaseAIChatModelOptions(
      enableCodeExecution: true,
    ),
  );
  
  final agent = Agent.fromModel(model);
  final response = await agent.send(
    'Write and execute Python code to calculate the first 10 Fibonacci numbers'
  );
  
  print('Code Execution Result: ${response}');
}
```

### Streaming with Accumulation

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';

Future<void> streamingExample() async {
  final agent = Agent('firebase:gemini-2.0-flash');
  final accumulator = FirebaseAIStreamingAccumulator(
    modelName: 'gemini-2.0-flash',
  );
  
  print('🚀 Streaming response:');
  
  await for (final chunk in agent.sendStream('Tell me a story about AI')) {
    // Accumulate chunks
    accumulator.add(chunk);
    
    // Stream individual chunks
    print(chunk.output.parts.whereType<TextPart>().first.text);
    
    // Show progress
    if (accumulator.chunkCount % 5 == 0) {
      print('\n📊 Progress: ${accumulator.chunkCount} chunks, '
            '${accumulator.accumulatedTextLength} chars');
    }
  }
  
  // Get final accumulated result
  final finalResult = accumulator.buildFinal();
  print('\n✅ Complete response:');
  print('- Total chunks: ${accumulator.chunkCount}');
  print('- Final length: ${accumulator.accumulatedTextLength} chars');
  print('- Has thinking: ${accumulator.hasThinking}');
  print('- Has safety ratings: ${accumulator.hasSafetyRatings}');
}
```

### Tool Calling

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:json_schema/json_schema.dart';

Future<void> toolCallingExample() async {
  // Define tools
  final tools = [
    Tool(
      name: 'get_weather',
      description: 'Get current weather for a location',
      inputSchema: JsonSchema.object({
        'location': JsonSchema.string(description: 'City name'),
        'units': JsonSchema.string(
          description: 'Temperature units',
          enumValues: ['celsius', 'fahrenheit'],
        ),
      }, requiredProperties: ['location']),
    ),
  ];
  
  final provider = FirebaseAIProvider();
  final model = provider.createChatModel(
    name: 'gemini-2.0-flash',
    tools: tools,
  );
  
  final agent = Agent.fromModel(model);
  final response = await agent.send(
    'What\'s the weather like in San Francisco?'
  );
  
  print('Tool Calling Response: ${response}');
}
```

### Typed Output

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:json_schema/json_schema.dart';

Future<void> typedOutputExample() async {
  final agent = Agent('firebase:gemini-2.0-flash');
  
  // Define output schema
  final schema = JsonSchema.object({
    'name': JsonSchema.string(description: 'Character name'),
    'class': JsonSchema.string(
      description: 'Character class',
      enumValues: ['warrior', 'mage', 'rogue'],
    ),
    'level': JsonSchema.integer(description: 'Character level (1-20)'),
    'stats': JsonSchema.object({
      'strength': JsonSchema.integer(),
      'intelligence': JsonSchema.integer(),
      'dexterity': JsonSchema.integer(),
    }),
  });
  
  final response = await agent.sendFor(
    'Create a fantasy RPG character',
    outputSchema: schema,
  );
  
  print('Typed Output: ${response}');
}
```

## Error Handling

The Firebase AI provider includes comprehensive error handling:

```dart
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';

Future<void> errorHandlingExample() async {
  try {
    final agent = Agent('firebase:gemini-2.0-flash');
    final response = await agent.send('Your message here');
    print(response);
  } catch (e) {
    if (e.toString().contains('quota')) {
      print('❌ Quota exceeded. Check your Firebase project billing.');
    } else if (e.toString().contains('safety')) {
      print('❌ Content filtered by safety guidelines.');
    } else if (e.toString().contains('permission')) {
      print('❌ Permission denied. Check Firebase project configuration.');
    } else {
      print('❌ Unexpected error: $e');
    }
  }
}
```

## Configuration Options

### Firebase AI Chat Model Options

```dart
const options = FirebaseAIChatModelOptions(
  // Generation parameters
  temperature: 0.7,
  topP: 0.9,
  topK: 40,
  maxOutputTokens: 2048,
  
  // Safety and behavior
  safetySettings: [
    // Configure safety settings
  ],
  stopSequences: ['END', 'STOP'],
  
  // Advanced features
  enableCodeExecution: true,
  responseMimeType: 'application/json', // For typed output
  responseSchema: yourJsonSchema,
);
```

## Best Practices

### 1. Firebase Configuration
- Ensure Firebase AI is enabled in your Firebase project
- Configure App Check for enhanced security
- Set up proper authentication if needed

### 2. Error Handling
- Always wrap Firebase AI calls in try-catch blocks
- Check for specific error types (quota, safety, permissions)
- Implement retry logic for transient failures

### 3. Media Validation
- Always validate media files before sending
- Respect size limits (20MB for images, 50MB for audio, 100MB for video)
- Use supported MIME types only

### 4. Performance Optimization
- Use streaming for long responses
- Implement response accumulation for better UX
- Consider model selection based on use case

### 5. Security
- Enable App Check for production deployments
- Implement proper content filtering
- Monitor usage and costs

## Supported Models

| Model | Description | Context Window | Capabilities |
|-------|-------------|----------------|--------------|
| `gemini-2.0-flash` | Latest and fastest | 1M tokens | Vision, Tools, Code Execution |
| `gemini-1.5-flash` | Fast multimodal | 1M tokens | Vision, Tools, Code Execution |  
| `gemini-1.5-pro` | Complex reasoning | 2M tokens | Vision, Tools, Advanced Reasoning |

## Provider Capabilities

- ✅ `ProviderCaps.chat` - Text generation
- ✅ `ProviderCaps.multiToolCalls` - Multiple tool calls
- ✅ `ProviderCaps.typedOutput` - Structured output
- ✅ `ProviderCaps.chatVision` - Image/video analysis
- ✅ `ProviderCaps.thinking` - Reasoning capture

## Integration with dartantic_ai

This provider is fully compatible with the dartantic_ai framework and supports:

- Agent-based interactions
- Multi-turn conversations  
- Tool orchestration
- Streaming responses
- Typed output generation
- Multi-modal inputs

## Troubleshooting

### Common Issues

1. **Firebase not initialized**
   ```
   Solution: Call Firebase.initializeApp() before using the provider
   ```

2. **Model not found**
   ```
   Solution: Ensure the model name is correct and available in your region
   ```

3. **Permission denied**
   ```
   Solution: Check Firebase project configuration and AI service enablement
   ```

4. **Quota exceeded**
   ```
   Solution: Check Firebase project quotas and billing settings
   ```

For more examples and advanced usage, see the `example/` directory in this package.