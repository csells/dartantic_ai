// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;

void main() async {
  final agent = Agent.forProvider(LoggingProvider());
  const prompt = 'Count from 1 to 5, one number at a time';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');
  final stream = agent.sendStream(prompt);
  await stream.forEach((chunk) => stdout.write(chunk.output));
  stdout.writeln();
  exit(0);
}

/// A custom HTTP client that logs all requests and responses
class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    print('🔵 HTTP ${request.method} ${request.url}');

    // Log request headers
    print('📋 Request Headers:');
    request.headers.forEach((key, value) {
      // Mask sensitive headers
      if (key.toLowerCase().contains('key') ||
          key.toLowerCase().contains('auth') ||
          key.toLowerCase().contains('token')) {
        print('   $key: [REDACTED]');
      } else {
        print('   $key: $value');
      }
    });

    // Log request body if present
    if (request is http.Request && request.body.isNotEmpty) {
      print('📝 Request Body:');
      try {
        final json = jsonDecode(request.body);
        print(const JsonEncoder.withIndent('  ').convert(json));
      } on FormatException {
        // Not JSON, print as-is
        print(request.body);
      }
    }

    // Send the request and time it
    final stopwatch = Stopwatch()..start();
    final response = await _inner.send(request);
    stopwatch.stop();

    // Buffer the response to log it (but still pass it through unchanged)
    final bytes = await response.stream.toBytes();
    final responseBody = utf8.decode(bytes);

    print(
      '\n🟢 HTTP ${response.statusCode} ${response.reasonPhrase} '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );

    // Log response headers
    print('📋 Response Headers:');
    response.headers.forEach((key, value) {
      print('   $key: $value');
    });

    // Log response body
    if (responseBody.isNotEmpty) {
      print('📝 Response Body:');
      try {
        final json = jsonDecode(responseBody);
        print(const JsonEncoder.withIndent('  ').convert(json));
      } on FormatException {
        // Not JSON, print as-is
        print(responseBody);
      }
    }

    print('\n${'=' * 60}\n'); // Separator for readability

    // Return a new response with the buffered bytes (unchanged)
    return http.StreamedResponse(
      Stream.fromIterable([bytes]),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// Custom provider that uses a logging HTTP client
class LoggingProvider extends GoogleProvider {
  LoggingProvider({super.apiKey});

  @override
  ChatModel<GoogleChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    GoogleChatModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    return GoogleChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      enableThinking: enableThinking,
      apiKey: apiKey!,
      baseUrl: baseUrl ?? GoogleProvider.defaultBaseUrl,
      client: LoggingHttpClient(),
      defaultOptions: GoogleChatModelOptions(
        temperature: temperature ?? options?.temperature,
        topP: options?.topP,
        maxOutputTokens: options?.maxOutputTokens,
        topK: options?.topK,
        candidateCount: options?.candidateCount,
        stopSequences: options?.stopSequences,
        responseMimeType: options?.responseMimeType,
        responseSchema: options?.responseSchema,
        safetySettings: options?.safetySettings,
        enableCodeExecution: options?.enableCodeExecution,
      ),
    );
  }
}
