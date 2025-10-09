# Firebase AI Provider Example

This example demonstrates how to use the Firebase AI provider with Dartantic AI in a Flutter application.

## Setup

1. **Configure Firebase**:
   ```bash
   # Install FlutterFire CLI
   dart pub global activate flutterfire_cli
   
   # Configure Firebase for your project
   flutterfire configure
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Enable Firebase AI** in your Firebase console:
   - Go to your Firebase project console
   - Navigate to "Build" > "AI Logic" 
   - Enable Firebase AI Logic

## Running the Example

```bash
flutter run
```

## Key Features Demonstrated

- **Basic Chat**: Send messages to Firebase AI (Gemini) models
- **Provider Setup**: Initialize Firebase AI provider correctly
- **Real-time Responses**: Display AI responses in a chat interface
- **Error Handling**: Handle and display errors gracefully

## Code Structure

- `main.dart`: Main application with Firebase initialization and chat UI
- The example shows how to:
  - Initialize Firebase
  - Create a Firebase AI provider
  - Create a chat model
  - Send messages and receive responses
  - Handle the response stream

## Important Notes

- This example requires a Flutter app (not pure Dart)
- Firebase must be properly configured for your project
- Firebase AI Logic must be enabled in your Firebase console
- The app uses Firebase authentication and App Check for security

## Extending the Example

You can extend this example to demonstrate:
- Tool calling with Firebase AI
- Typed output generation
- Multimodal inputs (images, etc.)
- Streaming responses with real-time updates
- Safety settings and content filtering