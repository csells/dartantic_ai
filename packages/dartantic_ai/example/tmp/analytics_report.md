# Dart CLI App - Analytics Report

## Overview

This guide provides comprehensive instructions for setting up, running, and troubleshooting a Dart CLI (Command Line Interface) application. Whether you're a beginner or an experienced developer, this document will help you get your Dart CLI app up and running.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation Steps](#installation-steps)
3. [Running the CLI App](#running-the-cli-app)
4. [Common Commands](#common-commands)
5. [Troubleshooting](#troubleshooting)
6. [Best Practices](#best-practices)

---

## Prerequisites

Before running a Dart CLI application, ensure you have the following installed:

- **Dart SDK** (version 2.12 or higher recommended)
- A terminal or command prompt
- Basic familiarity with command-line operations

### Checking if Dart is Installed

Run the following command to verify your Dart installation:

```bash
dart --version
```

If Dart is installed correctly, you should see output similar to:
```
Dart SDK version: 3.x.x (stable)
```

---

## Installation Steps

### Step 1: Install Dart SDK

#### On macOS (using Homebrew)

```bash
brew tap dart-lang/dart
brew install dart
```

#### On Windows (using Chocolatey)

```bash
choco install dart-sdk
```

#### On Linux

```bash
sudo apt-get update
sudo apt-get install apt-transport-https
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | sudo tee /etc/apt/sources.list.d/dart_stable.list
sudo apt-get update
sudo apt-get install dart
```

### Step 2: Set Up Your CLI Project

#### Clone or Create Your Project

If you're starting from scratch:

```bash
dart create -t console-simple my_cli_app
cd my_cli_app
```

If you're cloning an existing project:

```bash
git clone <repository-url>
cd <project-directory>
```

### Step 3: Install Dependencies

Navigate to your project directory and run:

```bash
dart pub get
```

This command downloads all the dependencies specified in your `pubspec.yaml` file.

---

## Running the CLI App

### Method 1: Using `dart run`

The standard way to run a Dart CLI app:

```bash
dart run
```

Or to run a specific file:

```bash
dart run bin/my_app.dart
```

### Method 2: Running with Arguments

Pass arguments to your CLI app:

```bash
dart run bin/my_app.dart --option value argument1 argument2
```

### Method 3: Compile and Run

For better performance, compile to native executable:

```bash
dart compile exe bin/my_app.dart -o my_app
./my_app
```

On Windows:
```bash
dart compile exe bin/my_app.dart -o my_app.exe
my_app.exe
```

### Method 4: Global Activation

To make your CLI app available system-wide:

```bash
dart pub global activate --source path .
my_cli_app
```

---

## Common Commands

### Package Management

```bash
# Get dependencies
dart pub get

# Update dependencies
dart pub upgrade

# Add a new dependency
dart pub add package_name

# Remove a dependency
dart pub remove package_name
```

### Development Commands

```bash
# Run the app in development
dart run

# Run with verbose output
dart --verbose run

# Run tests
dart test

# Format code
dart format .

# Analyze code for issues
dart analyze
```

### Building and Deployment

```bash
# Compile to executable
dart compile exe bin/main.dart -o output_name

# Compile to JavaScript
dart compile js bin/main.dart -o output.js

# Compile to JIT snapshot
dart compile jit-snapshot bin/main.dart -o output.jit
```

---

## Troubleshooting

### Issue 1: "dart: command not found"

**Problem:** Dart is not in your system PATH.

**Solution:**
- Verify Dart installation: Check if Dart is installed in the expected location
- Add Dart to PATH:
  - **macOS/Linux:** Add to `~/.bashrc` or `~/.zshrc`:
    ```bash
    export PATH="$PATH:/usr/lib/dart/bin"
    ```
  - **Windows:** Add Dart SDK bin directory to System Environment Variables

### Issue 2: "Pub get failed"

**Problem:** Unable to download dependencies.

**Solution:**
1. Check your internet connection
2. Verify `pubspec.yaml` syntax:
   ```bash
   dart pub get --verbose
   ```
3. Clear pub cache:
   ```bash
   dart pub cache repair
   ```
4. Delete `pubspec.lock` and `.dart_tool` folder, then run `dart pub get` again

### Issue 3: "Target of URI doesn't exist"

**Problem:** Import statements reference non-existent files.

**Solution:**
1. Run `dart pub get` to ensure all dependencies are installed
2. Check file paths in import statements
3. Verify that the referenced package is listed in `pubspec.yaml`
4. Restart your IDE/editor

### Issue 4: Permission Denied When Running Executable

**Problem:** Compiled executable lacks execution permissions.

**Solution (macOS/Linux):**
```bash
chmod +x my_app
./my_app
```

### Issue 5: Version Conflicts

**Problem:** Dependency version conflicts in `pubspec.yaml`.

**Solution:**
1. Review error messages carefully
2. Update dependency constraints in `pubspec.yaml`:
   ```yaml
   dependencies:
     package_name: ^2.0.0  # Use compatible version
   ```
3. Run `dart pub upgrade --major-versions` to upgrade to latest compatible versions

### Issue 6: "Unsupported operation" or Platform-Specific Errors

**Problem:** Code uses platform-specific features not available on current OS.

**Solution:**
- Use `Platform` class to detect OS:
  ```dart
  import 'dart:io';
  
  if (Platform.isWindows) {
    // Windows-specific code
  } else if (Platform.isLinux || Platform.isMacOS) {
    // Unix-like systems code
  }
  ```

### Issue 7: Slow Performance

**Problem:** CLI app runs slowly.

**Solution:**
1. Compile to native executable for production use
2. Profile your code:
   ```bash
   dart run --observe bin/main.dart
   ```
3. Optimize hot paths and reduce unnecessary computations

### Issue 8: Missing Arguments Error

**Problem:** App crashes when arguments are not provided.

**Solution:**
- Implement proper argument parsing with validation:
  ```dart
  import 'package:args/args.dart';
  
  void main(List<String> arguments) {
    final parser = ArgParser()
      ..addOption('name', abbr: 'n', defaultsTo: 'User');
    
    try {
      final results = parser.parse(arguments);
      final name = results['name'];
      print('Hello, $name!');
    } catch (e) {
      print('Error: $e');
      print('Usage: dart run bin/main.dart --name <name>');
      exit(1);
    }
  }
  ```

---

## Best Practices

### 1. Project Structure

Organize your Dart CLI project following the standard structure:

```
my_cli_app/
├── bin/
│   └── main.dart          # Entry point
├── lib/
│   ├── src/
│   │   ├── commands/      # Command implementations
│   │   ├── utils/         # Utility functions
│   │   └── models/        # Data models
│   └── my_cli_app.dart    # Public API
├── test/
│   └── *_test.dart        # Test files
├── pubspec.yaml           # Dependencies
└── README.md              # Documentation
```

### 2. Argument Parsing

Use the `args` package for robust command-line argument parsing:

```dart
import 'package:args/args.dart';

final parser = ArgParser()
  ..addFlag('verbose', abbr: 'v', help: 'Enable verbose output')
  ..addOption('output', abbr: 'o', help: 'Output file path');
```

### 3. Error Handling

Always handle errors gracefully:

```dart
try {
  // Your code here
} on FileSystemException catch (e) {
  stderr.writeln('File error: ${e.message}');
  exit(1);
} catch (e) {
  stderr.writeln('Unexpected error: $e');
  exit(1);
}
```

### 4. User Feedback

Provide clear output and progress indicators:

```dart
import 'dart:io';

stdout.writeln('Processing...');
stdout.write('Progress: ');
// Use carriage return for updating same line
stdout.write('\rProgress: 50%');
```

### 5. Testing

Write tests for your CLI logic:

```bash
dart test
```

### 6. Documentation

Document your CLI commands and options:

```bash
dart run bin/main.dart --help
```

### 7. Versioning

Include version information in your app:

```dart
const version = '1.0.0';

if (argResults['version']) {
  print('My CLI App v$version');
  exit(0);
}
```

---

## Additional Resources

- [Official Dart Documentation](https://dart.dev/guides)
- [Dart CLI Package Tutorial](https://dart.dev/tutorials/server/cmdline)
- [args Package Documentation](https://pub.dev/packages/args)
- [Effective Dart Style Guide](https://dart.dev/guides/language/effective-dart)

---

## Summary

Running a Dart CLI application involves:

1. **Installing** the Dart SDK
2. **Setting up** your project with `dart pub get`
3. **Running** with `dart run` or compiling to executable
4. **Troubleshooting** common issues using the solutions provided above
5. **Following best practices** for maintainable, user-friendly CLI apps

With this guide, you should be able to successfully run, debug, and maintain your Dart CLI applications. Happy coding!
