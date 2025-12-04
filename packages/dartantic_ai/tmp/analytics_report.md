# Dart CLI Application - Setup and Execution Guide

## Overview

This guide provides comprehensive instructions for setting up and running a Dart CLI (Command Line Interface) application, along with common troubleshooting steps.

## Prerequisites

Before running the Dart CLI app, ensure you have the following installed on your system:

- **Dart SDK** (version 2.17 or higher)
- **Git** (for cloning repositories)
- A terminal or command prompt

## Installation and Setup

### 1. Install Dart SDK

#### On Windows:
```bash
# Using Chocolatey
choco install dart-sdk

# Using Scoop
scoop install dart
```

#### On macOS:
```bash
# Using Homebrew
brew tap dart-lang/dart
brew install dart

# Using MacPorts
sudo port install dart
```

#### On Linux:
```bash
# Using APT (Debian/Ubuntu)
sudo apt update
sudo apt install dart

# Using Snap
sudo snap install dart
```

### 2. Verify Installation

Check if Dart is properly installed:

```bash
dart --version
```

Expected output should show the Dart SDK version.

### 3. Clone or Download the Project

```bash
# If using Git
git clone <repository-url>
cd <project-directory>

# Or download and extract the project files
```

### 4. Install Dependencies

Navigate to the project directory and install required packages:

```bash
dart pub get
```

## Running the CLI Application

### Basic Execution

There are several ways to run a Dart CLI application:

#### Method 1: Direct Execution
```bash
dart run bin/<app_name>.dart [arguments]
```

#### Method 2: Using pub run
```bash
dart pub run <package_name> [arguments]
```

#### Method 3: Compiled Executable
```bash
# First, compile the application
dart compile exe bin/<app_name>.dart -o <output_name>

# Then run the compiled executable
./<output_name> [arguments]
```

### Common Command Examples

```bash
# Run with help flag
dart run bin/analytics.dart --help

# Run with specific parameters
dart run bin/analytics.dart --input data.csv --output results.json

# Run with verbose logging
dart run bin/analytics.dart --verbose --config config.yaml
```

## Project Structure

A typical Dart CLI project structure:

```
project/
├── bin/
│   └── app_name.dart          # Main executable
├── lib/
│   ├── src/
│   │   ├── commands/          # Command implementations
│   │   ├── models/           # Data models
│   │   └── utils/            # Utility functions
│   └── app_name.dart         # Library exports
├── test/                     # Test files
├── pubspec.yaml             # Package configuration
└── README.md                # Project documentation
```

## Configuration

### Environment Variables

Some CLI apps may require environment variables:

```bash
# Set environment variables (Linux/macOS)
export API_KEY=your_api_key
export LOG_LEVEL=info

# Set environment variables (Windows)
set API_KEY=your_api_key
set LOG_LEVEL=info
```

### Configuration Files

Check if the app requires configuration files (usually `config.yaml` or `config.json`):

```yaml
# Example config.yaml
app_settings:
  debug: false
  timeout: 30
  output_format: json

api:
  endpoint: https://api.example.com
  version: v1
```

## Troubleshooting

### Common Issues and Solutions

#### 1. "dart: command not found"

**Problem**: Dart SDK is not installed or not in PATH.

**Solutions**:
- Reinstall Dart SDK following the installation steps above
- Add Dart to your system PATH:
  ```bash
  # Add to ~/.bashrc or ~/.zshrc (Linux/macOS)
  export PATH="$PATH:/usr/lib/dart/bin"
  
  # Windows: Add to System Environment Variables
  # Add C:\tools\dart-sdk\bin to PATH
  ```

#### 2. "pub get failed"

**Problem**: Dependencies cannot be resolved.

**Solutions**:
- Check internet connection
- Clear pub cache: `dart pub cache repair`
- Delete `pubspec.lock` and run `dart pub get` again
- Verify `pubspec.yaml` syntax

#### 3. "Target of URI doesn't exist"

**Problem**: Missing imports or incorrect file paths.

**Solutions**:
- Verify all import statements in the code
- Check if all required files exist
- Run `dart pub deps` to check dependencies

#### 4. Permission Denied (Linux/macOS)

**Problem**: Insufficient permissions to execute.

**Solution**:
```bash
chmod +x bin/<app_name>.dart
# Or for compiled executable
chmod +x <executable_name>
```

#### 5. OutOfMemoryError

**Problem**: Application runs out of memory.

**Solutions**:
- Increase VM memory: `dart --old_gen_heap_size=4096 run bin/app.dart`
- Optimize code to use less memory
- Process data in smaller chunks

#### 6. Package Version Conflicts

**Problem**: Conflicting package versions.

**Solutions**:
- Run `dart pub deps` to see dependency tree
- Update dependencies: `dart pub upgrade`
- Override specific versions in `pubspec.yaml`:
  ```yaml
  dependency_overrides:
    package_name: ^1.0.0
  ```

### Debug Mode

Run the application in debug mode for more detailed error information:

```bash
dart --enable-asserts run bin/<app_name>.dart [arguments]
```

### Logging and Verbose Output

Enable verbose output if the application supports it:

```bash
dart run bin/<app_name>.dart --verbose
# or
dart run bin/<app_name>.dart -v
```

## Performance Optimization

### Compilation Options

For better performance in production:

```bash
# Compile with optimizations
dart compile exe bin/<app_name>.dart -o <output_name>

# Compile with specific target
dart compile exe --target-os=<os> bin/<app_name>.dart -o <output_name>
```

### Memory Management

Monitor memory usage:

```bash
# Run with memory profiling
dart --observe run bin/<app_name>.dart
```

## Additional Resources

- [Dart SDK Documentation](https://dart.dev/tools/sdk)
- [Dart CLI Package Guidelines](https://dart.dev/tools/pub/cmd)
- [Dart Language Tour](https://dart.dev/language)
- [Effective Dart Style Guide](https://dart.dev/guides/language/effective-dart)

## Support

If you encounter issues not covered in this guide:

1. Check the application's README.md file
2. Look for issue trackers in the project repository
3. Consult the Dart community forums
4. Review application-specific documentation

---

*Last updated: [Current Date]*
*Version: 1.0*