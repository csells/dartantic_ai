// NEVER check for API keys in tests. Dartantic already validates API keys
// and throws a clear exception if one is missing. Tests should fail loudly
// when credentials are unavailable, not silently skip.

import 'dart:convert';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart'
    show AnthropicClientException;
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/chat_models/anthropic_chat/anthropic_server_side_tool_types.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_files_client.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_tool_deliverable_tracker.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Anthropic server-side tooling helpers', () {
    test(
      'mergeAnthropicServerToolConfigs combines enums and manual entries',
      () {
        const manualConfigs = [
          AnthropicServerToolConfig(
            type: 'web_search_20250305',
            name: 'web_search',
          ),
        ];
        final merged = mergeAnthropicServerToolConfigs(
          manualConfigs: manualConfigs,
          serverSideTools: const {AnthropicServerSideTool.codeInterpreter},
        );

        expect(merged, hasLength(2));
        expect(
          merged.map((tool) => '${tool.type}:${tool.name}'),
          containsAllInOrder([
            'web_search_20250305:web_search',
            'code_execution_20250825:code_execution',
          ]),
        );
      },
    );

    test('betaFeaturesForAnthropicTools deduplicates feature headers', () {
      const manualConfigs = [
        AnthropicServerToolConfig(
          type: 'code_execution_20250825',
          name: 'code_execution',
        ),
      ];
      final features = betaFeaturesForAnthropicTools(
        manualConfigs: manualConfigs,
        serverSideTools: const {
          AnthropicServerSideTool.codeInterpreter,
          AnthropicServerSideTool.webFetch,
        },
      );

      expect(
        features,
        containsAll(<String>[
          'code-execution-2025-05-22',
          'code-execution-2025-08-25',
          'files-api-2025-04-14',
          'web-fetch-2025-09-10',
        ]),
      );
      expect(features.toSet().length, features.length);
    });
  });

  const codeExecutionTool = AnthropicServerToolConfig(
    type: 'code_execution_20250825',
    name: 'code_execution',
  );

  const toolMetadataKeys = <String>[
    AnthropicServerToolTypes.codeExecution,
    AnthropicServerToolTypes.textEditorCodeExecution,
    AnthropicServerToolTypes.bashCodeExecution,
  ];

  const pdfPrompt =
      'Use the code execution tool to create a PDF named "summary.pdf" '
      'listing three reasons Dart is great for CLI utilities. After the tool '
      'finishes, print the three reasons to stdout so they appear in the '
      'response text.';

  group('Anthropic server-side tooling', () {
    test(
      'media stream surfaces code execution metadata',
      () async {
        final agent = Agent(
          'anthropic',
          chatModelOptions: const AnthropicChatOptions(
            serverSideTools: {AnthropicServerSideTool.codeInterpreter},
          ),
        );

        final streamedEvents = <Map<String, Object?>>[];
        List<MediaGenerationResult> chunks;
        try {
          chunks = await agent
              .generateMediaStream(
                pdfPrompt,
                mimeTypes: const ['application/pdf'],
              )
              .toList();
        } on AnthropicClientException catch (error) {
          final message = _anthropicErrorMessage(error);
          if (message != null &&
              message.contains('credit balance is too low')) {
            return;
          }
          rethrow;
        }

        for (final chunk in chunks) {
          for (final key in toolMetadataKeys) {
            final events = chunk.metadata[key];
            if (events is List) {
              streamedEvents.addAll(events.cast<Map<String, Object?>>());
            }
          }
        }

        expect(streamedEvents, isNotEmpty);

        final finalChunk = chunks.lastWhere(
          (chunk) => chunk.isComplete,
          orElse: () => chunks.last,
        );

        final aggregatedEvents = <Map<String, Object?>>[];
        for (final key in toolMetadataKeys) {
          final aggregated = finalChunk.metadata[key];
          if (aggregated is List) {
            aggregatedEvents.addAll(aggregated.cast<Map<String, Object?>>());
          }
        }
        expect(aggregatedEvents, isNotEmpty);
        expect(
          aggregatedEvents.any((event) => event.containsKey('tool_use_id')),
          isTrue,
        );
        expect(
          aggregatedEvents.any(
            (event) => jsonEncode(event).contains('file_id'),
          ),
          isTrue,
        );
        expect(chunks.any((chunk) => chunk.assets.isNotEmpty), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'media generation returns deliverables and tool metadata',
      () async {
        final agent = Agent(
          'anthropic',
          mediaModelOptions: const AnthropicMediaGenerationModelOptions(
            serverTools: [codeExecutionTool],
            // Media requests always require the code execution tool.
          ),
        );

        late final MediaGenerationResult result;
        try {
          result = await agent.generateMedia(
            pdfPrompt,
            mimeTypes: const ['application/pdf'],
          );
        } on AnthropicClientException catch (error) {
          final message = _anthropicErrorMessage(error);
          if (message != null &&
              message.contains('credit balance is too low')) {
            return;
          }
          rethrow;
        }

        final pdfAssets = result.assets.whereType<DataPart>().where(
          (asset) => asset.mimeType.contains('pdf'),
        );
        expect(pdfAssets, isNotEmpty);
        expect(pdfAssets.first.bytes.isNotEmpty, isTrue);
        final metadataList = <Map<String, Object?>>[];
        for (final key in toolMetadataKeys) {
          final toolMetadata = result.metadata[key];
          if (toolMetadata is List) {
            metadataList.addAll(toolMetadata.cast<Map<String, Object?>>());
          }
        }
        expect(metadataList, isNotEmpty);
        expect(
          metadataList.any(
            (event) =>
                jsonEncode(event).contains('file_id') ||
                jsonEncode(event).contains('container_upload'),
          ),
          isTrue,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('web search metadata produces link parts', () async {
      final tracker = AnthropicToolDeliverableTracker(
        AnthropicFilesClient(
          apiKey: '',
          betaFeatures: const [],
          client: MockClient((_) async => http.Response('{"data": []}', 200)),
        ),
        targetMimeTypes: const {'*/*'},
      );

      final emission = await tracker.handleMetadata({
        AnthropicServerToolTypes.webSearch: [
          {
            'type': 'web_search_tool_result',
            'tool_use_id': 'srvtoolu_test',
            'content': [
              {
                'type': 'web_search_result',
                'url': 'https://example.com/',
                'title': 'Example Domain',
              },
            ],
          },
        ],
      });

      final links = emission.links;
      expect(links, isNotEmpty);
      expect(links.first.url.toString(), 'https://example.com/');
    });

    test('web fetch metadata produces assets and links', () async {
      final tracker = AnthropicToolDeliverableTracker(
        AnthropicFilesClient(
          apiKey: '',
          betaFeatures: const [],
          client: MockClient((_) async => http.Response('{"data": []}', 200)),
        ),
        targetMimeTypes: const {'*/*'},
      );

      final emission = await tracker.handleMetadata({
        AnthropicServerToolTypes.webFetch: [
          {
            'type': 'web_fetch_tool_result',
            'tool_use_id': 'srvtoolu_fetch',
            'content': {
              'url': 'https://example.com/article',
              'content': {
                'title': 'Example Article',
                'source': {
                  'type': 'text',
                  'media_type': 'text/plain',
                  'data': 'Example article body',
                },
              },
            },
          },
        ],
      });

      final assets = emission.assets;
      final links = emission.links;
      expect(links, isNotEmpty);
      expect(links.first.url.toString(), 'https://example.com/article');
      expect(assets, isNotEmpty);
      final dataPart = assets.first as DataPart;
      expect(dataPart.mimeType, 'text/plain');
      expect(dataPart.bytes.isNotEmpty, isTrue);
    });
  });
}

String? _anthropicErrorMessage(AnthropicClientException error) {
  final body = error.body;
  if (body is Map) {
    final inner = body['error'];
    if (inner is Map) {
      final message = inner['message'];
      if (message is String) return message;
    }
  }
  if (body is String) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final inner = decoded['error'];
        if (inner is Map) {
          final message = inner['message'];
          if (message is String) return message;
        }
      }
    } on FormatException {
      // Ignore JSON parse errors; fall back to exception message.
    }
  }
  return error.message;
}
