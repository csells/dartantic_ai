/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_firebase.dart';

void main() {
  group('FirebaseAIProvider Backend Tests', () {
    setUpAll(() async {
      // Initialize mock Firebase for all tests
      await initializeMockFirebase();
    });
    test('can create provider with VertexAI backend (default)', () {
      final provider = FirebaseAIProvider();
      expect(provider.backend, equals(FirebaseAIBackend.vertexAI));
      expect(provider.displayName, equals('Firebase AI (Vertex AI)'));
    });

    test('can create provider with GoogleAI backend', () {
      final provider = FirebaseAIProvider(
        backend: FirebaseAIBackend.googleAI,
      );
      expect(provider.backend, equals(FirebaseAIBackend.googleAI));
      expect(provider.displayName, equals('Firebase AI (Google AI)'));
    });

    test('can create chat models with different backends', () {
      final vertexProvider = FirebaseAIProvider();
      final googleProvider = FirebaseAIProvider(
        backend: FirebaseAIBackend.googleAI,
      );

      final vertexModel = vertexProvider.createChatModel(
        name: 'gemini-2.0-flash',
      );
      final googleModel = googleProvider.createChatModel(
        name: 'gemini-2.0-flash',
      );

      expect(
        (vertexModel as FirebaseAIChatModel).backend,
        equals(FirebaseAIBackend.vertexAI),
      );
      expect(
        (googleModel as FirebaseAIChatModel).backend,
        equals(FirebaseAIBackend.googleAI),
      );
    });

    test('both backends have same capabilities', () {
      final vertexProvider = FirebaseAIProvider();
      final googleProvider = FirebaseAIProvider(
        backend: FirebaseAIBackend.googleAI,
      );

      expect(vertexProvider.caps, equals(googleProvider.caps));
    });
  });
}
