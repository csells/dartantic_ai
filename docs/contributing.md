# Contributing to dartantic_ai

We welcome contributions to dartantic_ai! This guide will help you get started with contributing to the project.

## How to Contribute

### 1. Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/csells/dartantic_ai.git
   cd dartantic_ai
   ```

### 2. Set Up Your Development Environment

Before making changes, ensure you can run the existing test suite successfully.

#### Install Dependencies

```bash
dart pub get
```

#### Set Up API Keys for Testing

To run the full test suite, you'll need API keys for various providers. Set these environment variables:

```bash
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export GEMINI_API_KEY="your-google-gemini-key"
export MISTRAL_API_KEY="your-mistral-key"
export COHERE_API_KEY="your-cohere-key"
export OPENROUTER_API_KEY="your-openrouter-key"
export TOGETHER_API_KEY="your-together-key"
```

**Note**: Ollama providers run locally and don't require API keys.

### 3. Run Tests

Verify your setup by running the existing tests:

```bash
# Run all tests
dart test

# Run a specific test file
dart test test/chat_models_test.dart

# Run tests with timeout for long-running suites
dart test --timeout=10m
```

All tests should pass before you make any changes.

### 4. Make Your Changes

1. Create a new branch for your feature:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the existing code style and patterns

3. **Add tests for your new feature** - This is critical!

### 5. Testing Your Changes

#### Test Requirements

- **Every new feature must have tests**
- Follow the testing philosophy in test files (no defensive programming)
- Test both success cases and edge cases
- Ensure your tests work across all applicable providers

#### Testing Best Practices

1. **No Exception Hiding**: Let exceptions bubble up for diagnosis
2. **Provider Filtering**: Only filter by capabilities (e.g., `ProviderCaps`)
3. **80/20 Rule**: Test common cases across all providers, edge cases on Google only
4. **No Duplication**: Each functionality should be tested in ONE file only

#### Example Test Pattern

```dart
void runProviderTest(
  String description,
  Future<void> Function(Provider provider) testFunction, {
  Set<ProviderCaps>? requiredCaps,
  bool edgeCase = false,
}) {
  final providers = edgeCase
      ? ['google:gemini-2.0-flash'] // Edge cases on Google only
      : Providers.all
          .where((p) => requiredCaps == null || 
                 requiredCaps.every((cap) => p.caps.contains(cap)))
          .map((p) => '${p.name}:${p.defaultModelNames[ModelKind.chat]}');

  for (final providerModel in providers) {
    test('$providerModel: $description', () async {
      final provider = Providers.get(providerModel.split(':')[0]);
      await testFunction(provider);
    });
  }
}
```

### 6. Verify Your Changes

Before submitting:

1. **Run all tests** and ensure they pass:
   ```bash
   dart test
   ```

2. **Format your code**:
   ```bash
   dart format .
   ```

3. **Analyze your code**:
   ```bash
   dart analyze
   ```

### 7. Submit Your Pull Request

1. Commit your changes with a clear message:
   ```bash
   git commit -m "feat: add support for new feature X"
   ```

2. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

3. Open a Pull Request on GitHub with:
   - Clear description of what you've added/changed
   - Reference to any related issues
   - Confirmation that all tests pass
   - Description of the tests you've added

## Code Style Guidelines

- Follow Dart conventions and the existing code style
- Use meaningful variable and function names
- Add documentation comments for public APIs
- Keep functions focused and single-purpose

## What Makes a Good Contribution?

- **Has tests**: No PR will be merged without appropriate tests
- **Follows patterns**: Uses existing patterns and conventions
- **Well documented**: Includes clear documentation
- **Focused**: Does one thing well rather than many things poorly
- **Compatible**: Works across all applicable providers

## Need Help?

If you have questions:

1. Check existing issues and discussions
2. Review the test files for examples
3. Open an issue for clarification

Thank you for contributing to dartantic_ai!