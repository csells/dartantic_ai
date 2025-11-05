// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_files_client.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_tool_deliverable_tracker.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';
import 'package:http/http.dart' as http;

void main(List<String> args) async {
  stdout.writeln('🧪 Anthropic Code Execution Tool Demo');

  final apiKey =
      Platform.environment['ANTHROPIC_API_KEY'] ??
      Platform.environment['ANTHROPIC_API_TEST_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'Set the ANTHROPIC_API_KEY environment variable before running this '
      'example. See packages/dartantic_ai/example/.env for details.',
    );
    return;
  }

  final filesClient = AnthropicFilesClient(
    apiKey: apiKey,
    betaFeatures: AnthropicServerSideTool.codeInterpreter.betaFeatures,
  );
  final tracker = AnthropicToolDeliverableTracker(
    filesClient,
    targetMimeTypes: const {'*/*'},
  );

  final agent = Agent(
    'anthropic:claude-sonnet-4-5-20250929',
    chatModelOptions: const AnthropicChatOptions(
      serverSideTools: {AnthropicServerSideTool.codeInterpreter},
      maxTokens: 4096, // Increase for server-side tool execution
    ),
  );

  const prompt = r'''
Create a markdown file named analytics_report.md that explains how to run a
Dart CLI app, including setup steps and troubleshooting guidance. After the file
exists, run the command
`cp /tmp/analytics_report.md "$OUTPUT_DIR/analytics_report.md" && ls "$OUTPUT_DIR"`
so the artifact appears in $OUTPUT_DIR before you finish.
''';

  final systemMessage = ChatMessage.system(r'''
You have access to Anthropic's server-side code execution tool. Whenever you
create or modify a file, you MUST copy it into the $OUTPUT_DIR directory before
you finish. After copying, run `ls "$OUTPUT_DIR"` to verify the artifact is
present. Do not conclude the task until the requested files are inside
$OUTPUT_DIR.
''');

  final savedAssetKeys = <String>{};
  final seenLinks = <String>{};
  final history = <ChatMessage>[];

  try {
    stdout.writeln('User: $prompt');
    stdout.writeln('Claude:');

    await for (final chunk in agent.sendStream(
      prompt,
      history: [systemMessage],
    )) {
      stdout.write(chunk.output);
      history.addAll(chunk.messages);
      await _saveDeliverablesFromMetadata(
        tracker,
        chunk.metadata,
        savedAssetKeys,
        seenLinks,
      );
      dumpMetadata(chunk.metadata, prefix: '\n');
    }

    await _finishDeliverableCollection(tracker, savedAssetKeys);
  } finally {
    filesClient.close();
  }

  final conversation = [systemMessage, ...history];

  _saveMessageDataParts(conversation, savedAssetKeys);
  if (savedAssetKeys.isEmpty) {
    stdout.writeln(
      '⚠️  No downloadable files were detected. Ensure Claude '
      r'copies files into $OUTPUT_DIR before finishing.',
    );
  }
  dumpMessages(conversation);

  stdout.writeln('✅ Completed code execution demo.');
}

class LoggingClient extends http.BaseClient {
  LoggingClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;
  Uri? lastUrl;
  Map<String, String>? lastHeaders;
  String? lastBody;
  int _responseCounter = 0;
  final _responseSnippets = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final originalLength = request.contentLength;
    final bodyBytes = await request.finalize().toBytes();
    lastUrl = request.url;
    lastHeaders = Map<String, String>.from(request.headers);
    lastBody = bodyBytes.isEmpty ? null : utf8.decode(bodyBytes);

    stdout.writeln('\n=== Anthropic HTTP Request ===');
    stdout.writeln('${request.method} ${request.url}');
    stdout.writeln('Headers: ${jsonEncode(lastHeaders)}');
    stdout.writeln('Body: ${lastBody ?? "<empty>"}');
    stdout.writeln('=============================\n');

    final forward = http.StreamedRequest(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..contentLength = originalLength != null && originalLength >= 0
          ? originalLength
          : bodyBytes.length;

    request.headers.forEach((key, value) {
      forward.headers[key] = value;
    });
    forward.sink.add(bodyBytes);
    await forward.sink.close();

    final streamed = await _inner.send(forward);

    // Stream the response while capturing it for logging
    final responseBuffer = StringBuffer();
    final controller = StreamController<List<int>>();

    streamed.stream.listen(
      (chunk) {
        responseBuffer.write(utf8.decode(chunk, allowMalformed: true));
        controller.add(chunk);
      },
      onError: controller.addError,
      onDone: () {
        _responseSnippets.add(
          '--- Response ${++_responseCounter} (${streamed.statusCode}) ---\n'
          '$responseBuffer\n',
        );
        controller.close();
      },
      cancelOnError: true,
    );

    return http.StreamedResponse(
      controller.stream,
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
      contentLength: streamed.contentLength,
    );
  }

  void dumpResponses() {
    if (_responseSnippets.isEmpty) {
      stdout.writeln('No responses captured.');
      return;
    }

    stdout.writeln('\n=== Anthropic HTTP Responses ===');
    for (final snippet in _responseSnippets) {
      stdout.writeln(snippet);
    }
    stdout.writeln('===============================\n');
  }

  @override
  void close() {
    _inner.close();
  }
}

const _outputDirectory = 'tmp';
int _downloadedFileCounter = 0;

Future<void> _saveDeliverablesFromMetadata(
  AnthropicToolDeliverableTracker tracker,
  Map<String, dynamic> metadata,
  Set<String> savedAssetKeys,
  Set<String> seenLinkUrls,
) async {
  if (metadata.isEmpty) return;

  final emission = await tracker.handleMetadata(metadata);
  if (emission.assets.isNotEmpty) {
    _saveDataParts(emission.assets, savedAssetKeys);
  }
  for (final link in emission.links) {
    final url = link.url.toString();
    if (seenLinkUrls.add(url)) {
      stdout.writeln('🔗 Tool link: $url');
    }
  }
}

Future<void> _finishDeliverableCollection(
  AnthropicToolDeliverableTracker tracker,
  Set<String> savedAssetKeys,
) async {
  final pending = await tracker.collectRecentFiles();
  if (pending.isEmpty) return;

  stdout.writeln(
    '📥 Retrieved ${pending.length} file(s) from the Anthropic Files API.',
  );
  _saveDataParts(pending, savedAssetKeys);
}

void _saveMessageDataParts(
  List<ChatMessage> messages,
  Set<String> savedAssetKeys,
) {
  final parts = messages.expand((message) => message.parts);
  _saveDataParts(parts, savedAssetKeys);
}

void _saveDataParts(Iterable<Part> parts, Set<String> savedAssetKeys) {
  for (final part in parts) {
    if (part is! DataPart) continue;

    final fileName = _resolveFileName(part);
    final key = '$fileName:${part.bytes.length}:${part.mimeType}';
    if (!savedAssetKeys.add(key)) continue;

    final file = File('$_outputDirectory/$fileName');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(part.bytes);
    stdout.writeln(
      '💾 Saved file: ${file.path} '
      '(${part.mimeType}, ${part.bytes.length} bytes)',
    );
  }
}

String _resolveFileName(DataPart part) {
  final candidate = part.name?.trim();
  if (candidate != null && candidate.isNotEmpty) {
    final sanitized = _sanitizeFileName(candidate);
    if (sanitized.isNotEmpty) return sanitized;
  }

  final extension = Part.extensionFromMimeType(part.mimeType);
  final index = ++_downloadedFileCounter;
  final generated = extension == null
      ? 'anthropic_file_$index'
      : 'anthropic_file_$index.$extension';
  return _sanitizeFileName(generated);
}

String _sanitizeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[\\/:<>\"|?*\r\n]+'), '_').trim();
  if (sanitized.isNotEmpty) return sanitized;
  return 'anthropic_file_${++_downloadedFileCounter}';
}
