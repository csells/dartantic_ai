// ignore_for_file: avoid_print, unreachable_from_main, unused_element

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';
import 'package:json_schema/json_schema.dart';

void main() async {
  await singleMcpServer();
  await multipleToolsAndMcpServers();
  await oneRequestMultiTool();
  exit(0);
}

Future<void> singleMcpServer() async {
  print('\nSingle MCP Server');

  final huggingFace = McpClient.remote(
    'huggingface',
    url: Uri.parse('https://hf.co/mcp'),
  );

  final hgTools = await huggingFace.listTools();
  dumpTools('huggingface', hgTools);

  final agent = Agent('google', tools: [...hgTools]);

  const query = 'Who is hugging face?';
  await agent.sendStream(query).forEach((r) => stdout.write(r.output));
  stdout.writeln();
}

Future<void> multipleToolsAndMcpServers() async {
  print('\nMultiple Tools and MCP Servers');

  final localTime = Tool(
    name: 'local_time',
    description: 'Returns the current local time in ISO 8601 format.',
    onCall: (args) async => {'result': DateTime.now().toIso8601String()},
  );

  final location = Tool(
    name: 'location',
    description: 'Returns the current location.',
    onCall: (args) async => {'result': 'Portland, OR'},
  );

  final deepwiki = McpClient.remote(
    'deepwiki',
    url: Uri.parse('https://mcp.deepwiki.com/mcp'),
  );

  final dwTools = await deepwiki.listTools();
  dumpTools('deepwiki', dwTools);

  final huggingFace = McpClient.remote(
    'huggingface',
    url: Uri.parse('https://huggingface.co/mcp'),
  );

  final hgTools = await huggingFace.listTools();

  final agent = Agent(
    'google',
    tools: [localTime, location, ...dwTools, ...hgTools],
  );

  const query =
      'Where am I and what time is it and '
      'who is hugging face and '
      'what model providers does csells/dartantic_ai currently support?';

  final history = <ChatMessage>[];
  await agent.sendStream(query).forEach((r) {
    stdout.write(r.output);
    history.addAll(r.messages);
  });
  stdout.writeln();

  dumpMessages(history);
}

Future<void> oneRequestMultiTool() async {
  print('\nOne Request, Multi Tool Calls');

  final agent = Agent(
    'openai',
    tools: [
      Tool(
        name: 'get-current-date-time',
        description: 'Get the current local date and time in ISO-8601 format',
        onCall: (_) async => {'datetime': DateTime.now().toIso8601String()},
      ),
      Tool<Map<String, dynamic>>(
        name: 'get-calendar-schedule',
        description: 'Get the schedule for the day',
        inputSchema: JsonSchema.create({
          'type': 'object',
          'properties': {
            'date': {'type': 'string', 'format': 'date'},
          },
          'required': ['date'],
        }),

        onCall: (args) async => {
          'result': '[${args['date']}: You have a meeting at 10:00 AM',
        },
      ),
    ],
  );

  final messages = <ChatMessage>[];
  await agent
      .sendStream("What's on my schedule today?", history: messages)
      .forEach((r) {
        messages.addAll(r.messages);
        stdout.write(r.output);
      });

  dumpMessages(messages);
}
