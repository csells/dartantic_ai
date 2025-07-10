// ignore_for_file: non_constant_identifier_names

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart' show Agent;

/// Environment variables for the example.
///
/// This makes it easy to get and check the environment variables all at once
/// to make it easy to feed to the [Agent] class via [Agent.environment].
class Env {
  // `Platform.environment` works well for Dart, but not for Flutter. Use
  // `static const FOO = String.fromEnvironment('FOO');` instead, passing in the
  // values via `flutter run --dart-define=FOO=...` This technique builds the
  // values into the app at compile-time which is why it works across platforms.
  static final GEMINI_API_KEY = Platform.environment['GEMINI_API_KEY'];
  static final OPENAI_API_KEY = Platform.environment['OPENAI_API_KEY'];
  static final OPENROUTER_API_KEY = Platform.environment['OPENROUTER_API_KEY'];
  static final ANTHROPIC_API_KEY = Platform.environment['ANTHROPIC_API_KEY'];

  static String tryGet(String key, {String? defaultValue}) {
    final value = switch (key) {
      'GEMINI_API_KEY' => GEMINI_API_KEY,
      'OPENAI_API_KEY' => OPENAI_API_KEY,
      'OPENROUTER_API_KEY' => OPENROUTER_API_KEY,
      'ANTHROPIC_API_KEY' => ANTHROPIC_API_KEY,
      _ => throw Exception('Unknown environment variable: $key'),
    };

    if (value == null) {
      if (defaultValue != null) return defaultValue;
      throw Exception('Environment variable $key is not set');
    }
    return value;
  }

  static Map<String, String> get tryAll => {
    'GEMINI_API_KEY': tryGet('GEMINI_API_KEY'),
    'OPENAI_API_KEY': tryGet('OPENAI_API_KEY'),
    'OPENROUTER_API_KEY': tryGet('OPENROUTER_API_KEY'),
    'ANTHROPIC_API_KEY': tryGet('ANTHROPIC_API_KEY'),
  };
}
