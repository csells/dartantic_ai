import 'package:logging/logging.dart';

import 'agent/agent.dart';
import 'platform/platform.dart';

/// Configuration options for logging in the dartantic_ai package.
///
/// Provides simple control over logging level, filtering, and output handling
/// for all dartantic loggers through the [Agent.loggingOptions] property.
///
/// Example usage:
/// ```dart
/// // Use defaults (Level.INFO, no filtering, print to console)
/// Dartantic.loggingOptions = LoggingOptions();
///
/// // Filter to only OpenAI operations
/// Dartantic.loggingOptions = LoggingOptions(filter: 'openai');
///
/// // Custom level and handler
/// Dartantic.loggingOptions = LoggingOptions(
///   level: Level.FINE,
///   filter: 'dartantic.chat',
///   onRecord: (record) => myLogger.log(record),
/// );
/// ```
class LoggingOptions {
  /// Creates logging options with the specified configuration.
  ///
  /// All parameters have sensible defaults:
  /// - [level]: Defaults to [Level.INFO] for balanced visibility
  /// - [filter]: Defaults to empty string (matches all logger names)
  /// - [onRecord]: Defaults to formatted console output
  const LoggingOptions({
    this.level = Level.INFO,
    this.filter = '',
    this.onRecord = _defaultOnRecord,
  });

  /// Creates logging options reading level from DARTANTIC_LOG_LEVEL environment
  /// variable.
  ///
  /// Supported environment values: FINE, INFO, WARNING, SEVERE, OFF
  /// Falls back to [Level.INFO] if not set or invalid.
  ///
  /// Example usage:
  /// ```bash
  /// DARTANTIC_LOG_LEVEL=FINE dart run example/bin/single_turn_chat.dart
  /// ```
  factory LoggingOptions.fromEnvironment({
    String? filter,
    void Function(LogRecord)? onRecord,
  }) {
    final envLevel = _parseLevelFromEnvironment();
    return LoggingOptions(
      level: envLevel,
      filter: filter ?? '',
      onRecord: onRecord ?? _defaultOnRecord,
    );
  }

  /// Parses log level from DARTANTIC_LOG_LEVEL environment variable.
  static Level _parseLevelFromEnvironment() {
    final envValue = tryGetEnv('DARTANTIC_LOG_LEVEL');
    if (envValue == null || envValue.isEmpty) return Level.INFO;

    return switch (envValue.toUpperCase()) {
      'FINE' => Level.FINE,
      'INFO' => Level.INFO,
      'WARNING' => Level.WARNING,
      'SEVERE' => Level.SEVERE,
      'OFF' => Level.OFF,
      _ => Level.INFO, // Default for invalid values
    };
  }

  /// The minimum logging level to capture.
  ///
  /// Only log records at or above this level will be processed.
  /// Defaults to [Level.INFO].
  final Level level;

  /// Substring filter for logger names.
  ///
  /// Only log records whose logger name contains this string will be
  /// processed. Use empty string to match all logger names.
  ///
  /// Examples:
  /// - `'openai'` matches `dartantic.chat.providers.openai`
  /// - `'chat'` matches all chat-related loggers
  /// - `'http'` matches HTTP-related loggers
  /// - `''` matches all loggers (default)
  final String filter;

  /// Callback function to handle log records.
  ///
  /// Receives a [LogRecord] for each log entry that passes the level
  /// and filter criteria. Defaults to formatted console output.
  final void Function(LogRecord) onRecord;

  /// Creates a copy of this [LoggingOptions] with optionally updated values.
  LoggingOptions copyWith({
    Level? level,
    String? filter,
    void Function(LogRecord)? onRecord,
  }) => LoggingOptions(
    level: level ?? this.level,
    filter: filter ?? this.filter,
    onRecord: onRecord ?? this.onRecord,
  );

  @override
  String toString() => 'LoggingOptions(level: $level, filter: "$filter")';
}

/// Default log record handler that prints formatted output to console.
void _defaultOnRecord(LogRecord record) =>
    // ignore: avoid_print
    print('[${record.loggerName}] ${record.level.name}: ${record.message}');
