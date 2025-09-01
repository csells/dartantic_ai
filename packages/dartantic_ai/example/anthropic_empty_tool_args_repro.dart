// Minimal, standalone repro for dartantic_ai streaming tool-args bug
// Run from repo root:
//   dart run repros/anthropic_empty_tool_args_repro.dart

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';

void main() async {
  Agent.loggingOptions = LoggingOptions(
    // level: Level.ALL,
    // filter: 'dartantic',
    onRecord: (r) {
      // Keep concise; errors/stack are printed explicitly
      stdout.writeln('🔍 [${r.level.name}] ${r.loggerName}: ${r.message}');
      if (r.error != null) stdout.writeln('   Error: ${r.error}');
      if (r.stackTrace != null) stdout.writeln('   Stack: ${r.stackTrace}');
    },
  );

  // Bridge Anthropic key for dartantic
  // 1) Prefer ANTHROPIC_API_TEST_KEY from process env (if present)
  // 2) Load .env (from CWD or parent) for ANTHROPIC_API_KEY
  void setKey(String key) {
    if (key.isEmpty) return;
    Agent.environment['ANTHROPIC_API_KEY'] = key;
  }

  final testKey = Platform.environment['ANTHROPIC_API_TEST_KEY'];
  if (testKey != null && testKey.isNotEmpty) {
    setKey(testKey);
    print('🔑 Anthropic key detected via ANTHROPIC_API_TEST_KEY');
  } else {
    // Try loading from .env in CWD, then ../.env
    final candidates = <String>['.env', '../.env'];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        final lines = const LineSplitter().convert(file.readAsStringSync());
        for (final raw in lines) {
          final line = raw.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final idx = line.indexOf('=');
          if (idx <= 0) continue;
          final k = line.substring(0, idx).trim();
          var v = line.substring(idx + 1).trim();
          if ((v.startsWith('"') && v.endsWith('"')) ||
              (v.startsWith("'") && v.endsWith("'"))) {
            v = v.substring(1, v.length - 1);
          }
          if (k == 'ANTHROPIC_API_KEY') {
            setKey(v);
          }
        }
        if (Agent.environment.containsKey('ANTHROPIC_API_KEY')) {
          print('🔑 Anthropic key loaded from $path');
          break;
        }
      }
    }
  }

  // 3) Create a single tool that commonly triggers the issue
  var callCount = 0;
  final writeFile = Tool<Map<String, dynamic>>(
    name: 'write_file',
    description: 'Create or overwrite a file',
    inputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'Relative path'},
        'content': {'type': 'string', 'description': 'File content'},
      },
      'required': ['path', 'content'],
    }),
    onCall: (args) async {
      callCount++;
      stdout.writeln('🛠️ Tool call #$callCount path=${args['path']}');

      if (args.isEmpty) {
        try {
          stdout.writeln('❌ EMPTY ARGS DETECTED (count=$callCount)');
          // Stop fast once we prove the bug
          stdout.writeln('\n🐛 BUG REPRODUCED: received empty tool args');
          // Exit immediately to keep repro minimal and reliable (Returning here
          // avoids exit() so test harnesses can capture output.)
          throw Exception('Empty args detected');
        } on Exception catch (e, st) {
          stdout.writeln('💥 Error during repro: $e');
          stdout.writeln(st);
          exit(1);
        }
      }

      final path = (args as Map)['path'];
      return {'status': 'success', 'path': path};
    },
  );

  // 4) Build a simple agent (Anthropic streaming with one tool)
  final agent = Agent(
    // Using explicit model string; provider default also works
    // 'anthropic:claude-3-5-sonnet-20241022',
    // 'google:gemini-2.5-pro',
    // 'openai:gpt-5',
    'openai',
    // 'anthropic',
    // 'google',
    tools: [writeFile],
  );

  // 5) A task that forces multiple tool calls with sufficiently large inputs
  //    to trigger streaming of tool input (increasing likelihood of the bug)
  const task = '''
Create these 6 files using the write_file tool ONLY. For each file:
- Provide both path and content
- Make content at least 1200 characters (docs + code) to force streaming
- Do not output anything except tool calls

Files:
1. lib/a.dart - A class with docs and methods
2. lib/b.dart - B class with docs and methods
3. lib/c.dart - C class with docs and methods
4. lib/d.dart - D class with docs and methods
5. lib/e.dart - E class with docs and methods
6. lib/f.dart - F class with docs and methods
''';

  stdout.writeln(
    '🚀 Starting minimal repro (this should reproduce empty args).',
  );
  try {
    // Guard the overall run so it doesn't hang forever if something changes
    final result = await agent.send(
      task,
      history: [
        ChatMessage.system(
          'You are a code generator. Use write_file for each file. '
          'ALWAYS include required fields path and content.',
        ),
      ],
    )
    // .timeout(const Duration(minutes: 1))
    ;
    stdout.writeln('ℹ️ Agent finished without reproducing empty args.');
    stdout.writeln('Output (first 400 chars):');
    stdout.writeln(
      result.output.length > 400
          ? '${result.output.substring(0, 400)}...'
          : result.output,
    );
  } on Exception catch (e, st) {
    stdout.writeln('💥 Error during repro: $e');
    stdout.writeln(st);
  }
  exit(0);
}
