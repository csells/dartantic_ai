// ignore_for_file: avoid_print, unreachable_from_main, unused_element

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

late final List<Tool> hgTools;

void main() async {
  hgTools = await McpClient.remote(
    'huggingface',
    url: Uri.parse('https://huggingface.co/mcp'),
    headers: {
      'Authorization': 'Bearer ${Platform.environment['HUGGINGFACE_TOKEN']!}',
    },
  ).listTools();

  const model = 'gemini:gemini-2.5-pro';
  await singleMcpServer(model);
  await multipleToolsAndMcpServers(model);
  exit(0);
}

Future<void> singleMcpServer(String model) async {
  print('\nSingle MCP Server');

  final agent = Agent(model, tools: hgTools);
  const query = 'Who is hugging face?';
  await agent
      .sendStream(query, history: [ChatMessage.system('be brief')])
      .forEach((r) => stdout.write(r.output));
  stdout.writeln();
}

Future<void> multipleToolsAndMcpServers(String model) async {
  print('\nMultiple Tools and MCP Servers');

  final c7Tools = await McpClient.remote(
    'context7',
    url: Uri.parse('https://mcp.context7.com/mcp'),
    headers: {'CONTEXT7_API_KEY': Platform.environment['CONTEXT7_API_KEY']!},
  ).listTools();

  final agent = Agent(
    model,
    tools: [localTimeTool, locationTool, ...hgTools, ...c7Tools],
  );

  const query =
      'Where am I and what time is it and '
      'who is hugging face and '
      'what does context7 say about whether dartantic_ai support tool calling '
      '(yes or no)?';

  final history = <ChatMessage>[];
  await agent
      .sendStream(query, history: [ChatMessage.system('be brief')])
      .forEach((r) {
        stdout.write(r.output);
        history.addAll(r.messages);
      });
  stdout.writeln();

  dumpMessages(history);
}
