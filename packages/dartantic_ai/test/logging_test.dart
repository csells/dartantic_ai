/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g.
///    ProviderTestCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('Agent Logging Features', () {
    late LoggingOptions originalOptions;

    setUp(() {
      // Save original options
      originalOptions = Agent.loggingOptions;
    });

    tearDown(() {
      // Restore original options
      Agent.loggingOptions = originalOptions;
    });

    group('basic logging configuration (80% cases)', () {
      test('can set logging level', () {
        final logs = <LogRecord>[];
        Agent.loggingOptions = LoggingOptions(
          level: Level.WARNING,
          onRecord: logs.add,
        );

        // This should be logged (WARNING >= WARNING)
        Logger('dartantic.test').warning('Warning message');

        // This should NOT be logged (INFO < WARNING)
        Logger('dartantic.test').info('Info message');

        // Allow async processing
        expect(logs.length, equals(1));
        expect(logs.first.message, equals('Warning message'));
      });

      test('can filter by logger name', () {
        final logs = <LogRecord>[];
        Agent.loggingOptions = LoggingOptions(
          level: Level.ALL,
          filter: 'openai',
          onRecord: logs.add,
        );

        // These should be logged (contains 'openai')
        Logger('dartantic.chat.providers.openai').info('OpenAI message 1');
        Logger('dartantic.openai.client').info('OpenAI message 2');

        // These should NOT be logged (doesn't contain 'openai')
        Logger('dartantic.chat.providers.anthropic').info('Anthropic message');
        Logger('dartantic.agent').info('Agent message');

        expect(logs.length, equals(2));
        expect(logs.every((log) => log.loggerName.contains('openai')), isTrue);
      });

      test('can use custom log handler', () {
        final customLogs = <String>[];
        Agent.loggingOptions = LoggingOptions(
          onRecord: (record) {
            customLogs.add('CUSTOM: ${record.level} - ${record.message}');
          },
        );

        Logger('dartantic.test').info('Test message');

        expect(customLogs, ['CUSTOM: INFO - Test message']);
      });
    });

    group('agent operation logging (80% cases)', () {
      test('agent operations produce logs when enabled', () async {
        final logs = <LogRecord>[];
        Agent.loggingOptions = LoggingOptions(
          level: Level.INFO,
          onRecord: logs.add,
        );

        // Run an agent operation
        final agent = Agent('openai:gpt-4o-mini');
        await agent.send('Say "test"');

        // Should have produced some logs
        expect(logs, isNotEmpty);
        expect(logs.any((log) => log.loggerName.contains('dartantic')), isTrue);
      });

      test('streaming operations produce logs when enabled', () async {
        final logs = <LogRecord>[];
        Agent.loggingOptions = LoggingOptions(
          level: Level.FINE,
          onRecord: logs.add,
        );

        // Run a streaming operation
        final agent = Agent('openai:gpt-4o-mini');
        final chunks = <String>[];
        await for (final chunk in agent.sendStream('Say "test"')) {
          chunks.add(chunk.output);
          if (chunks.length >= 3) break; // Limit chunks
        }

        // Should have produced logs
        expect(logs, isNotEmpty);
        expect(logs.any((log) => log.level == Level.FINE), isTrue);
      });

      test('no logs produced when logging disabled', () async {
        final logs = <LogRecord>[];
        Agent.loggingOptions = LoggingOptions(
          level: Level.OFF,
          onRecord: logs.add,
        );

        // Run an agent operation
        final agent = Agent('openai:gpt-4o-mini');
        await agent.send('Say "test"');

        // Should NOT have produced any logs
        expect(logs, isEmpty);
      });
    });

    group('log filtering combinations', () {
      test('level and name filters work together', () {
        final logs = <LogRecord>[];
        Agent.loggingOptions = LoggingOptions(
          level: Level.WARNING,
          filter: 'anthropic',
          onRecord: logs.add,
        );

        // Should be logged (WARNING level, contains 'anthropic')
        Logger('dartantic.anthropic').warning('Anthropic warning');

        // Should NOT be logged (INFO < WARNING, even though has 'anthropic')
        Logger('dartantic.anthropic').info('Anthropic info');

        // Should NOT be logged (WARNING level, but doesn't contain 'anthropic')
        Logger('dartantic.openai').warning('OpenAI warning');

        expect(logs.length, equals(1));
        expect(logs.first.message, equals('Anthropic warning'));
      });
    });

    group('edge cases', () {
      test('changing options updates logging immediately', () {
        final logs1 = <LogRecord>[];
        final logs2 = <LogRecord>[];

        // First configuration
        Agent.loggingOptions = LoggingOptions(
          filter: 'openai',
          onRecord: logs1.add,
        );

        Logger('dartantic.openai').info('Message 1');
        expect(logs1.length, equals(1));

        // Change configuration
        Agent.loggingOptions = LoggingOptions(
          filter: 'anthropic',
          onRecord: logs2.add,
        );

        Logger('dartantic.openai').info('Message 2');
        Logger('dartantic.anthropic').info('Message 3');

        // logs1 should not receive new messages
        expect(logs1.length, equals(1));
        // logs2 should only receive anthropic message
        expect(logs2.length, equals(1));
        expect(logs2.first.message, equals('Message 3'));
      });

      test('empty filter matches all loggers', () {
        final logs = <LogRecord>[];
        Agent.loggingOptions = LoggingOptions(
          filter: '', // Empty filter
          onRecord: logs.add,
        );

        Logger('dartantic.openai').info('OpenAI');
        Logger('dartantic.anthropic').info('Anthropic');
        Logger('other.logger').info('Other');

        expect(logs.length, equals(3));
      });
    });
  });
}
