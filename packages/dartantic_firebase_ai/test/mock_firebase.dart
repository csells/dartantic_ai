import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets up Firebase core mocks for testing without requiring a real Firebase project
Future<void> initializeMockFirebase() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the Firebase platform
  FirebasePlatform.instance = MockFirebasePlatform();

  // Initialize Firebase with mock options
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'mock-api-key',
      appId: 'mock-app-id',
      messagingSenderId: 'mock-sender-id',
      projectId: 'mock-project-id',
    ),
  );
}

/// Mock Firebase platform implementation for testing
class MockFirebasePlatform extends FirebasePlatform {
  MockFirebasePlatform() : super();

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => MockFirebaseApp(
      name: name ?? defaultFirebaseAppName,
      options:
          options ??
          const FirebaseOptions(
            apiKey: 'mock-api-key',
            appId: 'mock-app-id',
            messagingSenderId: 'mock-sender-id',
            projectId: 'mock-project-id',
          ),
    );

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => MockFirebaseApp(
      name: name,
      options: const FirebaseOptions(
        apiKey: 'mock-api-key',
        appId: 'mock-app-id',
        messagingSenderId: 'mock-sender-id',
        projectId: 'mock-project-id',
      ),
    );
}

/// Mock Firebase app implementation for testing
class MockFirebaseApp extends FirebaseAppPlatform {
  MockFirebaseApp({required String name, required FirebaseOptions options})
    : super(name, options);
}
