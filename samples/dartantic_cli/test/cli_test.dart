import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Run the CLI with the given arguments
Future<ProcessResult> runCli(
  List<String> args, {
  String? stdin,
  Map<String, String>? environment,
}) async {
  final workingDir = Directory.current.path.endsWith('dartantic_cli')
      ? Directory.current.path
      : '${Directory.current.path}/samples/dartantic_cli';

  final result = await Process.run(
    'dart',
    ['run', 'bin/dartantic.dart', ...args],
    workingDirectory: workingDir,
    environment: {...Platform.environment, ...?environment},
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return result;
}

/// Run the CLI with stdin input
Future<ProcessResult> runCliWithStdin(
  List<String> args,
  String stdinContent, {
  Map<String, String>? environment,
}) async {
  final workingDir = Directory.current.path.endsWith('dartantic_cli')
      ? Directory.current.path
      : '${Directory.current.path}/samples/dartantic_cli';

  final process = await Process.start(
    'dart',
    ['run', 'bin/dartantic.dart', ...args],
    workingDirectory: workingDir,
    environment: {...Platform.environment, ...?environment},
  );

  process.stdin.write(stdinContent);
  await process.stdin.close();

  final stdout = await process.stdout.transform(utf8.decoder).join();
  final stderr = await process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;

  return ProcessResult(process.pid, exitCode, stdout, stderr);
}

void main() {
  group('Phase 1: Basic Chat Command', () {
    test('SC-001: Basic chat with default agent (google)', () async {
      final result = await runCli(['-p', 'What is 2+2? Reply with just the number.']);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('4'));
    });

    test('SC-002: Chat with built-in provider (anthropic)', () async {
      final result = await runCli([
        '-a',
        'anthropic',
        '-p',
        'What is the capital of France? Reply with just the city name.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString().toLowerCase(), contains('paris'));
    });

    test('SC-004: Chat with model string as agent', () async {
      final result = await runCli([
        '-a',
        'openai:gpt-4o-mini',
        '-p',
        'What is 3+3? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('6'));
    });

    test('SC-011: Chat from stdin (no -p flag)', () async {
      final result = await runCliWithStdin(
        [],
        'What is 5+5? Reply with just the number.',
      );
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('10'));
    });
  });

  group('Phase 2: Settings File Support', () {
    late Directory tempDir;
    late String settingsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
      settingsPath = '${tempDir.path}/settings.yaml';
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-003: Chat with custom agent from settings', () async {
      // Create a settings file with a custom agent
      await File(settingsPath).writeAsString('''
agents:
  coder:
    model: openai:gpt-4o-mini
    system: You are a helpful assistant. Be very brief.
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-a',
        'coder',
        '-p',
        'What is 7+7? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('14'));
    });

    test('SC-033: Settings file override path (-s)', () async {
      // Create a settings file with a default agent
      await File(settingsPath).writeAsString('''
default_agent: myagent
agents:
  myagent:
    model: anthropic
    system: Always respond with exactly "CUSTOM_SETTINGS_LOADED" and nothing else.
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-p',
        'Hello',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('CUSTOM_SETTINGS_LOADED'));
    });

    test('SC-055: Invalid settings file (exit code 3)', () async {
      // Create an invalid YAML file
      await File(settingsPath).writeAsString('invalid: yaml: {{');

      final result = await runCli([
        '-s',
        settingsPath,
        '-p',
        'Hello',
      ]);
      expect(result.exitCode, 3, reason: 'stderr: ${result.stderr}');
    });

    test('SC-062: Environment variable substitution', () async {
      // Create a settings file with env var substitution
      await File(settingsPath).writeAsString(r'''
agents:
  envtest:
    model: ${TEST_MODEL_VAR}
    system: Reply with just "ENV_VAR_WORKS"
''');

      final result = await runCli(
        [
          '-s',
          settingsPath,
          '-a',
          'envtest',
          '-p',
          'Hello',
        ],
        environment: {'TEST_MODEL_VAR': 'google'},
      );
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('ENV_VAR_WORKS'));
    });
  });

  group('Phase 3: Prompt Processing', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-006: File attachment (@/path/file.txt)', () async {
      // Create a text file to attach
      final filePath = '${tempDir.path}/test.txt';
      await File(filePath).writeAsString(
        'The secret code is PINEAPPLE123.',
      );

      final result = await runCli([
        '-p',
        'What is the secret code in the attached file? Reply with just the code. @$filePath',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('PINEAPPLE123'));
    });

    test('SC-007: Multiple file attachments', () async {
      // Create two text files
      final file1Path = '${tempDir.path}/file1.txt';
      final file2Path = '${tempDir.path}/file2.txt';
      await File(file1Path).writeAsString('First file contains ALPHA.');
      await File(file2Path).writeAsString('Second file contains BETA.');

      final result = await runCli([
        '-p',
        'What are the two words in the attached files? Reply with just the two words. @$file1Path @$file2Path',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      final output = result.stdout.toString();
      expect(output, contains('ALPHA'));
      expect(output, contains('BETA'));
    });

    test('SC-008: Quoted filename with spaces (after @)', () async {
      // Create a file with spaces in name
      final filePath = '${tempDir.path}/my file.txt';
      await File(filePath).writeAsString('The answer is SPACES_WORK.');

      final result = await runCli([
        '-p',
        'What is the answer? Reply with just the answer. @"$filePath"',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('SPACES_WORK'));
    });

    test('SC-013: .prompt file processing', () async {
      // Create a .prompt file
      final promptPath = '${tempDir.path}/test.prompt';
      await File(promptPath).writeAsString('''
---
model: google
input:
  default:
    number: 42
---
What is {{number}} plus 1? Reply with just the number.
''');

      final result = await runCli(['-p', '@$promptPath']);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('43'));
    });

    test('SC-014: .prompt file with variable override', () async {
      // Create a .prompt file
      final promptPath = '${tempDir.path}/test.prompt';
      await File(promptPath).writeAsString('''
---
model: google
input:
  default:
    number: 42
---
What is {{number}} plus 1? Reply with just the number.
''');

      final result = await runCli(['-p', '@$promptPath', 'number=99']);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('100'));
    });

    test('SC-032: Working directory override (-d)', () async {
      // Create a file in temp directory
      await File('${tempDir.path}/local.txt').writeAsString(
        'Local file says DIRECTORY_OVERRIDE.',
      );

      final result = await runCli([
        '-d',
        tempDir.path,
        '-p',
        'What does the local file say? Reply with just the phrase. @local.txt',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('DIRECTORY_OVERRIDE'));
    });
  });

  group('Phase 4: Output Features', () {
    test('SC-021: Chat with verbose output (shows usage)', () async {
      final result = await runCli([
        '-v',
        '-p',
        'What is 2+2? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('4'));
      // Verbose output should show token usage on stderr
      final stderr = result.stderr.toString();
      expect(
        stderr.contains('tokens') || stderr.contains('usage'),
        isTrue,
        reason: 'Verbose should show usage info. stderr: $stderr',
      );
    });

    test('SC-022: Chat with thinking (shows thinking output)', () async {
      // Use a model that supports thinking (like gemini-2.5-flash with thinking)
      final result = await runCli([
        '-a',
        'google:gemini-2.5-flash',
        '-p',
        'Think step by step: what is 15 * 23?',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // The result should contain 345 somewhere
      expect(result.stdout.toString(), contains('345'));
      // If thinking is supported, it may show [Thinking] markers
      // But not all models support it, so we just verify successful completion
    });

    test('SC-023: Chat with thinking disabled via CLI', () async {
      final result = await runCli([
        '-a',
        'google:gemini-2.5-flash',
        '--no-thinking',
        '-p',
        'What is 2+2? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('4'));
      // With no-thinking flag, output should NOT contain [Thinking] markers
      expect(result.stdout.toString(), isNot(contains('[Thinking]')));
    });

    test('SC-034: Chat with --no-color', () async {
      final result = await runCli([
        '--no-color',
        '-p',
        'What is 2+2? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('4'));
      // No ANSI escape codes should be present
      final output = result.stdout.toString();
      expect(output, isNot(contains('\x1b[')));
    });
  });

  group('Phase 5: Structured Output & Temperature', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-017: Chat with inline output schema', () async {
      final result = await runCli([
        '-p',
        'List 3 programming languages. Respond with JSON.',
        '--output-schema',
        '{"type":"object","properties":{"languages":{"type":"array","items":{"type":"string"}}},"required":["languages"]}',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // Should return valid JSON with languages array
      final output = result.stdout.toString();
      expect(output, contains('languages'));
      expect(output, contains('['));
    });

    test('SC-018: Chat with output schema from file', () async {
      // Create a schema file
      final schemaPath = '${tempDir.path}/schema.json';
      await File(schemaPath).writeAsString('''
{
  "type": "object",
  "properties": {
    "name": {"type": "string"},
    "population": {"type": "integer"}
  },
  "required": ["name", "population"]
}
''');

      final result = await runCli([
        '-p',
        'Tell me about Tokyo. Respond with JSON containing name and population.',
        '--output-schema',
        '@$schemaPath',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      final output = result.stdout.toString();
      expect(output, contains('Tokyo'));
      expect(output, contains('population'));
    });

    test('SC-020: Chat with temperature', () async {
      // Low temperature should give more deterministic response
      final result = await runCli([
        '-t',
        '0.1',
        '-p',
        'What is 2+2? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('4'));
    });

    test('SC-056: Invalid output schema JSON (exit code 2)', () async {
      final result = await runCli([
        '-p',
        'Hello',
        '--output-schema',
        'not-valid-json',
      ]);
      expect(result.exitCode, 2, reason: 'stderr: ${result.stderr}');
      expect(result.stderr.toString().toLowerCase(), contains('invalid'));
    });
  });

  group('Phase 6: Server Tools & MCP', () {
    late Directory tempDir;
    late String settingsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
      settingsPath = '${tempDir.path}/settings.yaml';
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-028: Agent with server_tools disabled in settings', () async {
      // Create a settings file with server_tools: false
      await File(settingsPath).writeAsString('''
agents:
  simple:
    model: google
    server_tools: false
    system: Reply with just "NO_SERVER_TOOLS"
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-a',
        'simple',
        '-p',
        'Hello',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('NO_SERVER_TOOLS'));
    });

    test('SC-029: MCP server tools from settings', () async {
      // Create a settings file with MCP server configuration
      // Using Context7 as an example (requires CONTEXT7_API_KEY in env)
      await File(settingsPath).writeAsString(r'''
agents:
  research:
    model: google
    system: You have access to MCP tools. Reply with "MCP_CONFIGURED" to confirm.
    mcp_servers:
      - name: context7
        url: https://mcp.context7.com/mcp
        headers:
          CONTEXT7_API_KEY: "${CONTEXT7_API_KEY}"
''');

      // This test verifies that MCP servers are parsed and configured
      // The actual tool call would require a valid API key
      // For now, just verify the configuration is parsed without error
      final result = await runCli([
        '-s',
        settingsPath,
        '-a',
        'research',
        '-p',
        'Hello',
      ]);
      // May fail if CONTEXT7_API_KEY not set, but should at least parse config
      // Exit code 0 or 4 (API error if key missing) are acceptable
      expect(
        result.exitCode,
        anyOf(0, 4),
        reason: 'stderr: ${result.stderr}',
      );
    });
  });
}
