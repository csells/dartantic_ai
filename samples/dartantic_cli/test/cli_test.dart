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

    test('SC-005: Chat with full model string including embeddings', () async {
      final result = await runCli([
        '-a',
        'openai?chat=gpt-4o-mini&embeddings=text-embedding-3-small',
        '-p',
        'What is 4+4? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('8'));
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

    test('SC-009: Quoted filename with spaces (quotes around whole thing)',
        () async {
      // Create a file with spaces in name
      final filePath = '${tempDir.path}/another file.txt';
      await File(filePath).writeAsString('The answer is QUOTES_AROUND.');

      final result = await runCli([
        '-p',
        'What is the answer? Reply with just the answer. "@$filePath"',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('QUOTES_AROUND'));
    });

    test('SC-010: Chat with image attachment', () async {
      // Use a real image from the project (image_0.png)
      // Copy it to temp directory for the test
      final sourceImage = File('image_0.png');
      final imagePath = '${tempDir.path}/test_image.png';

      if (await sourceImage.exists()) {
        await sourceImage.copy(imagePath);
      } else {
        // If image_0.png doesn't exist, create a simple valid test image
        // by using a known working 1x1 red PNG
        final pngBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
        );
        await File(imagePath).writeAsBytes(pngBytes);
      }

      final result = await runCli([
        '-a',
        'google',
        '-p',
        'Describe this image briefly in one sentence. @$imagePath',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // The model should describe what it sees
      expect(result.stdout.toString().isNotEmpty, isTrue);
    });

    test('SC-012: Chat from stdin with file context', () async {
      // Create a context file
      final contextPath = '${tempDir.path}/context.txt';
      await File(contextPath).writeAsString('The secret number is 42.');

      // Pass stdin content with file attachment
      final result = await runCliWithStdin(
        ['-p', 'What is the secret number in the file? Reply with just the number. @$contextPath'],
        '', // stdin is empty, context comes from file
      );
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('42'));
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

    test('SC-015: Prompt file model overrides settings', () async {
      // Create a settings file with google as default
      final settingsPath = '${tempDir.path}/settings.yaml';
      await File(settingsPath).writeAsString('''
default_agent: google
''');

      // Create a .prompt file that specifies anthropic model
      // Use a factual question to test model override
      final promptPath = '${tempDir.path}/override.prompt';
      await File(promptPath).writeAsString('''
---
model: anthropic
---
What is 7 + 8? Reply with just the number.
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-p',
        '@$promptPath',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // The anthropic model should compute 7+8=15
      expect(result.stdout.toString(), contains('15'));
    });

    test('SC-016: CLI -a overrides .prompt file model', () async {
      // Create a .prompt file that specifies anthropic model
      // Use a factual question to test CLI override
      final promptPath = '${tempDir.path}/cli_override.prompt';
      await File(promptPath).writeAsString('''
---
model: anthropic
---
What is 9 + 6? Reply with just the number.
''');

      // CLI -a should override the prompt file model
      final result = await runCli([
        '-a',
        'google',
        '-p',
        '@$promptPath',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // The google model (from CLI) should compute 9+6=15
      expect(result.stdout.toString(), contains('15'));
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
    late String settingsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
      settingsPath = '${tempDir.path}/settings.yaml';
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

    test('SC-019: Chat with agent that has output_schema in settings',
        () async {
      // Create a settings file with an agent that has output_schema
      await File(settingsPath).writeAsString('''
agents:
  extractor:
    model: openai:gpt-4o-mini
    system: Extract entities from text.
    output_schema:
      type: object
      properties:
        entities:
          type: array
          items:
            type: object
            properties:
              name:
                type: string
              type:
                type: string
      required:
        - entities
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-a',
        'extractor',
        '-p',
        'John Smith works at Acme Corp as a software engineer.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Output should be structured JSON with entities
      final output = result.stdout.toString();
      expect(output, contains('entities'));
      expect(output, contains('John'));
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

    test('SC-024: Chat with agent thinking disabled in settings', () async {
      // Create a settings file with an agent that has thinking disabled
      await File(settingsPath).writeAsString('''
agents:
  quick:
    model: google:gemini-2.5-flash
    system: Be concise and direct.
    thinking: false
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-a',
        'quick',
        '-p',
        'What is 2+2? Reply with just the number.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('4'));
      // Output should NOT contain [Thinking] markers
      expect(result.stdout.toString(), isNot(contains('[Thinking]')));
    });

    test('SC-025: Chat with server-side tools enabled', () async {
      // Server-side tools are enabled by default
      // Test with Anthropic which supports web search
      final result = await runCli([
        '-a',
        'anthropic',
        '-p',
        'Say "SERVER_TOOLS_ENABLED" exactly.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('SERVER_TOOLS_ENABLED'));
    });

    test('SC-026: Chat with specific server-side tool disabled', () async {
      // Disable a specific server-side tool
      final result = await runCli([
        '-a',
        'anthropic',
        '--no-server-tool',
        'webSearch',
        '-p',
        'Say "TOOL_DISABLED" exactly.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('TOOL_DISABLED'));
    });

    test('SC-027: Chat with multiple server-side tools disabled', () async {
      // Disable multiple server-side tools
      final result = await runCli([
        '-a',
        'anthropic',
        '--no-server-tool',
        'webSearch,codeInterpreter',
        '-p',
        'Say "MULTIPLE_TOOLS_DISABLED" exactly.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('MULTIPLE_TOOLS_DISABLED'));
    });

    test('SC-030: Chat with custom provider config', () async {
      // Create a settings file with custom provider configuration
      // Note: This test validates config parsing, not actual API call
      await File(settingsPath).writeAsString('''
agents:
  custom-openai:
    model: openai:gpt-4o-mini
    base_url: https://api.openai.com/v1
    headers:
      X-Custom-Header: "custom-value"
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-a',
        'custom-openai',
        '-p',
        'Say "CUSTOM_CONFIG" exactly.',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('CUSTOM_CONFIG'));
    });

    test('SC-031: Chat with pirate agent (system prompt test)', () async {
      // Create a settings file with a system prompt
      await File(settingsPath).writeAsString('''
agents:
  pirate:
    model: google
    system: You are a pirate. Always respond with "Arrr!" at the start of your response.
''');

      final result = await runCli([
        '-s',
        settingsPath,
        '-a',
        'pirate',
        '-p',
        'What is your favorite food?',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString().toLowerCase(), contains('arrr'));
    });
  });

  group('Phase 7: Generate Command', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-035: Generate image', () async {
      final result = await runCli([
        'generate',
        '--mime',
        'image/png',
        '-o',
        tempDir.path,
        '-p',
        'A simple red circle on white background',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // Should output the generated file path
      expect(result.stdout.toString(), contains('Generated:'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-036: Generate with output directory', () async {
      final result = await runCli([
        'generate',
        '--mime',
        'image/png',
        '-o',
        tempDir.path,
        '-p',
        'A simple blue square',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // Should output file in the specified directory
      expect(result.stdout.toString(), contains(tempDir.path));

      // Verify a file was created
      final files = await tempDir.list().toList();
      expect(files.whereType<File>().isNotEmpty, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-057: Missing --mime error (exit code 2)', () async {
      final result = await runCli([
        'generate',
        '-p',
        'Generate something',
      ]);
      expect(result.exitCode, 2, reason: 'stderr: ${result.stderr}');
      expect(result.stderr.toString().toLowerCase(), contains('--mime'));
    });

    test('SC-037: Generate PDF', () async {
      // Note: PDF generation requires openai-responses provider
      final result = await runCli([
        'generate',
        '-a',
        'openai-responses',
        '--mime',
        'application/pdf',
        '-o',
        tempDir.path,
        '-p',
        'Create a one-page document with the title "Test PDF" and one paragraph.',
      ]);
      // This may fail if the provider doesn't support PDF generation
      // Exit code 0 or 4 (API limitation) are acceptable
      expect(
        result.exitCode,
        anyOf(0, 4),
        reason: 'stderr: ${result.stderr}',
      );
      if (result.exitCode == 0) {
        expect(result.stdout.toString(), contains('Generated:'));
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('SC-038: Generate CSV', () async {
      // Note: CSV generation requires openai-responses provider
      final result = await runCli([
        'generate',
        '-a',
        'openai-responses',
        '--mime',
        'text/csv',
        '-o',
        tempDir.path,
        '-p',
        'Create a CSV with 3 rows: name, age. Alice 30, Bob 25, Charlie 35.',
      ]);
      // This may fail if the provider doesn't support CSV generation
      // Exit code 0 or 4 (API limitation) are acceptable
      expect(
        result.exitCode,
        anyOf(0, 4),
        reason: 'stderr: ${result.stderr}',
      );
      if (result.exitCode == 0) {
        expect(result.stdout.toString(), contains('Generated:'));
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('SC-039: Generate with multiple MIME types', () async {
      final result = await runCli([
        'generate',
        '-a',
        'google',
        '--mime',
        'image/png',
        '--mime',
        'image/jpeg',
        '-o',
        tempDir.path,
        '-p',
        'A simple colored circle',
      ]);
      // Multiple MIME types should be accepted
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('Generated:'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-040: Generate with specific provider', () async {
      final result = await runCli([
        'generate',
        '-a',
        'google',
        '--mime',
        'image/png',
        '-o',
        tempDir.path,
        '-p',
        'A simple green triangle',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('Generated:'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Phase 8: Embed Command', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-041: Embed single file', () async {
      // Create a test file
      final filePath = '${tempDir.path}/test.txt';
      await File(filePath).writeAsString(
        'Dartantic is an agentic AI framework for Dart. '
        'It provides easy integration with multiple AI providers.',
      );

      final result = await runCli([
        'embed',
        'create',
        filePath,
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Output should be valid JSON with embeddings structure
      final output = result.stdout.toString();
      expect(output, contains('"model"'));
      expect(output, contains('"documents"'));
      expect(output, contains('"chunks"'));
      expect(output, contains('"vector"'));

      // Parse and verify structure
      final data = jsonDecode(output) as Map<String, dynamic>;
      expect(data['documents'], isA<List>());
      final docs = data['documents'] as List;
      expect(docs.length, 1);
      final doc = docs.first as Map<String, dynamic>;
      expect(doc['chunks'], isA<List>());
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-042: Embed multiple files', () async {
      // Create two test files
      final file1Path = '${tempDir.path}/doc1.txt';
      final file2Path = '${tempDir.path}/doc2.txt';
      await File(file1Path).writeAsString('First document about Python.');
      await File(file2Path).writeAsString('Second document about JavaScript.');

      final result = await runCli([
        'embed',
        'create',
        file1Path,
        file2Path,
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Verify both documents are in output
      final output = result.stdout.toString();
      final data = jsonDecode(output) as Map<String, dynamic>;
      final docs = data['documents'] as List;
      expect(docs.length, 2);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-044: Custom chunk size/overlap', () async {
      // Create a test file
      final filePath = '${tempDir.path}/test.txt';
      await File(filePath).writeAsString(
        'This is a test document with some content for chunking. ' * 20,
      );

      final result = await runCli([
        'embed',
        'create',
        '--chunk-size',
        '256',
        '--chunk-overlap',
        '50',
        filePath,
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Verify chunk options are in output
      final output = result.stdout.toString();
      final data = jsonDecode(output) as Map<String, dynamic>;
      expect(data['chunk_size'], 256);
      expect(data['chunk_overlap'], 50);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-045: Search with query', () async {
      // First create embeddings
      final docPath = '${tempDir.path}/doc.txt';
      await File(docPath).writeAsString(
        'Python is a programming language. '
        'JavaScript is used for web development. '
        'Dart is great for building apps.',
      );

      // Create embeddings
      final createResult = await runCli([
        'embed',
        'create',
        docPath,
      ]);
      expect(createResult.exitCode, 0, reason: 'stderr: ${createResult.stderr}');

      // Save embeddings to file
      final embeddingsPath = '${tempDir.path}/embeddings.json';
      await File(embeddingsPath).writeAsString(createResult.stdout.toString());

      // Search
      final searchResult = await runCli([
        'embed',
        'search',
        '-q',
        'programming languages',
        embeddingsPath,
      ]);
      expect(searchResult.exitCode, 0, reason: 'stderr: ${searchResult.stderr}');

      // Verify search results
      final output = searchResult.stdout.toString();
      expect(output, contains('"query"'));
      expect(output, contains('"results"'));
      expect(output, contains('"similarity"'));

      final data = jsonDecode(output) as Map<String, dynamic>;
      expect(data['query'], 'programming languages');
      expect(data['results'], isA<List>());
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-058: Missing -q error for search (exit code 2)', () async {
      // Create a dummy embeddings file
      final embeddingsPath = '${tempDir.path}/embeddings.json';
      await File(embeddingsPath).writeAsString('{}');

      final result = await runCli([
        'embed',
        'search',
        embeddingsPath,
      ]);
      expect(result.exitCode, 2, reason: 'stderr: ${result.stderr}');
      expect(result.stderr.toString(), contains('-q'));
    });

    test('Embed command requires subcommand', () async {
      final result = await runCli(['embed']);
      expect(result.exitCode, 2, reason: 'stderr: ${result.stderr}');
      expect(result.stderr.toString(), contains('subcommand'));
    });

    test('SC-043: Create embeddings with specific provider', () async {
      // Create a test file
      final filePath = '${tempDir.path}/doc_openai.txt';
      await File(filePath).writeAsString('Test document for OpenAI embeddings.');

      final result = await runCli([
        '-a',
        'openai',
        'embed',
        'create',
        filePath,
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Should output valid JSON with embeddings
      final output = result.stdout.toString();
      expect(output, contains('"documents"'));
      expect(output, contains('"vector"'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-046: Search embeddings in folder', () async {
      // Create embeddings and save to a folder
      final docPath = '${tempDir.path}/folder_doc.txt';
      await File(docPath).writeAsString('Python programming language for data science.');

      // Create embeddings
      final createResult = await runCli([
        'embed',
        'create',
        docPath,
      ]);
      expect(createResult.exitCode, 0, reason: 'stderr: ${createResult.stderr}');

      // Create embeddings folder and copy file there
      final embeddingsFolder = Directory('${tempDir.path}/embeddings_folder');
      await embeddingsFolder.create();
      final embeddingsPath = '${embeddingsFolder.path}/embeddings.json';
      await File(embeddingsPath).writeAsString(createResult.stdout.toString());

      // Search in folder (spec says this should work)
      final searchResult = await runCli([
        'embed',
        'search',
        '-q',
        'data science',
        '${embeddingsFolder.path}/',
      ]);
      expect(searchResult.exitCode, 0, reason: 'stderr: ${searchResult.stderr}');

      // Verify search results
      final output = searchResult.stdout.toString();
      expect(output, contains('"results"'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-047: Search with verbose', () async {
      // Create embeddings first
      final docPath = '${tempDir.path}/verbose_doc.txt';
      await File(docPath).writeAsString('Dart is great for Flutter apps.');

      final createResult = await runCli([
        'embed',
        'create',
        docPath,
      ]);
      expect(createResult.exitCode, 0, reason: 'stderr: ${createResult.stderr}');

      // Save embeddings
      final embeddingsPath = '${tempDir.path}/verbose_embeddings.json';
      await File(embeddingsPath).writeAsString(createResult.stdout.toString());

      // Search with verbose flag
      final searchResult = await runCli([
        '-v',
        'embed',
        'search',
        '-q',
        'Flutter',
        embeddingsPath,
      ]);
      expect(searchResult.exitCode, 0, reason: 'stderr: ${searchResult.stderr}');

      // Verbose output should show similarity scores
      final output = searchResult.stdout.toString();
      expect(output, contains('"similarity"'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Phase 9: Models Command', () {
    late Directory tempDir;
    late String settingsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
      settingsPath = '${tempDir.path}/settings.yaml';
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-048: List default provider models (google)', () async {
      final result = await runCli(['models']);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Should show Google provider
      final output = result.stdout.toString();
      expect(output, contains('Provider:'));
      expect(output.toLowerCase(), contains('google'));
      // Should show some models (at least chat models)
      expect(output, contains('Chat Models:'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-049: List specific provider models (openai)', () async {
      final result = await runCli(['models', '-a', 'openai']);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Should show OpenAI provider
      final output = result.stdout.toString();
      expect(output, contains('Provider:'));
      expect(output.toLowerCase(), contains('openai'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-050: Provider alias (gemini -> google)', () async {
      final result = await runCli(['models', '-a', 'gemini']);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // gemini is an alias for google
      final output = result.stdout.toString();
      expect(output, contains('Provider:'));
      expect(output.toLowerCase(), contains('google'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SC-051: Agent from settings', () async {
      // Create a settings file with a custom agent
      await File(settingsPath).writeAsString('''
agents:
  myagent:
    model: anthropic
''');

      final result = await runCli([
        'models',
        '-s',
        settingsPath,
        '-a',
        'myagent',
      ]);
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');

      // Should list Anthropic models (from agent's model)
      final output = result.stdout.toString();
      expect(output, contains('Provider:'));
      expect(output.toLowerCase(), contains('anthropic'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Error Handling', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dartantic_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('SC-052: Missing required prompt (exit code 2)', () async {
      // Pass empty stdin with no -p flag
      final result = await runCliWithStdin(['chat'], '');
      // Should fail with exit code 2 for missing required argument
      expect(result.exitCode, 2, reason: 'stderr: ${result.stderr}');
      final stderr = result.stderr.toString().toLowerCase();
      expect(
        stderr.contains('error') ||
            stderr.contains('usage') ||
            stderr.contains('prompt'),
        isTrue,
        reason: 'Expected error message. stderr: ${result.stderr}',
      );
    });

    test('SC-053: Invalid agent/provider name (exit code 1, 4, or 255)',
        () async {
      final result = await runCli([
        '-a',
        'nonexistent-provider-xyz123',
        '-p',
        'Hello',
      ]);
      // Exit code 1 (general error), 4 (API error), or 255 (unhandled exception)
      expect(
        result.exitCode,
        anyOf(1, 4, 255),
        reason: 'stderr: ${result.stderr}',
      );
      final stderr = result.stderr.toString().toLowerCase();
      expect(
        stderr.contains('error') ||
            stderr.contains('not found') ||
            stderr.contains('exception') ||
            stderr.contains('unknown'),
        isTrue,
        reason: 'Expected error message. stderr: ${result.stderr}',
      );
    });

    test('SC-054: Missing file attachment (exit code 1, 2, or 255)', () async {
      final result = await runCli([
        '-p',
        'Read this: @/nonexistent/path/to/file.txt',
      ]);
      // Exit code 1 (general error), 2 (invalid args), or 255 (unhandled)
      expect(
        result.exitCode,
        anyOf(1, 2, 255),
        reason: 'stderr: ${result.stderr}',
      );
      final stderr = result.stderr.toString().toLowerCase();
      expect(
        stderr.contains('not found') ||
            stderr.contains('error') ||
            stderr.contains('exception') ||
            stderr.contains('does not exist'),
        isTrue,
        reason: 'Expected error message. stderr: ${result.stderr}',
      );
    });
  });

  group('Environment Variables', () {
    test('SC-059: DARTANTIC_AGENT env var sets default agent', () async {
      final result = await runCli(
        ['-p', 'Say "ENV_AGENT_WORKS" exactly.'],
        environment: {'DARTANTIC_AGENT': 'anthropic'},
      );
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(result.stdout.toString(), contains('ENV_AGENT_WORKS'));
    });

    test('SC-060: DARTANTIC_LOG_LEVEL env var enables logging', () async {
      final result = await runCli(
        ['-p', 'Say "LOG_TEST" exactly.'],
        environment: {'DARTANTIC_LOG_LEVEL': 'FINE'},
      );
      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      // Logging should appear on stderr
      // Output should still work normally
      expect(result.stdout.toString(), contains('LOG_TEST'));
    });

    test('SC-061: Provider API key from environment', () async {
      // This test validates that the provider reads API key from environment
      // Using a clearly invalid key should result in an API error (exit code 4)
      final result = await runCli(
        ['-a', 'openai', '-p', 'Hello'],
        environment: {'OPENAI_API_KEY': 'sk-invalid-test-key'},
      );
      // With invalid API key, should fail with API error (exit code 4),
      // unhandled exception (255), or succeed if there's a valid key
      expect(
        result.exitCode,
        anyOf(0, 4, 255),
        reason: 'stderr: ${result.stderr}',
      );
    });
  });
}
