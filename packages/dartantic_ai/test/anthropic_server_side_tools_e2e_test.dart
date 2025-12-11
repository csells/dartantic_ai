// NEVER check for API keys in tests. Dartantic already validates API keys
// and throws a clear exception if one is missing. Tests should fail loudly
// when credentials are unavailable, not silently skip.

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

void main() {
  group('Anthropic server-side tooling E2E', () {
    test(
      'Code Interpreter: generates a PDF file',
      () async {
        final agent = Agent(
          'anthropic',
          chatModelOptions: const AnthropicChatOptions(
            serverSideTools: {AnthropicServerSideTool.codeInterpreter},
          ),
        );

        final result = await agent.generateMedia(
          'Use the code execution tool to create a PDF named "test.pdf" '
          'containing the text "Hello from Dartantic E2E".',
          mimeTypes: const ['application/pdf'],
        );

        expect(result.assets, isNotEmpty);
        final pdfAsset = result.assets.whereType<DataPart>().firstWhere(
          (asset) => asset.mimeType == 'application/pdf',
        );
        expect(pdfAsset, isA<DataPart>());
        expect(pdfAsset.bytes, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Web Search: searches and returns results',
      () async {
        final agent = Agent(
          'anthropic',
          chatModelOptions: const AnthropicChatOptions(
            serverSideTools: {AnthropicServerSideTool.webSearch},
          ),
        );

        final result = await agent.send(
          'Search for "Dart programming language" and tell me the release year '
          'of version 1.0.',
        );

        expect(result.output, isNotEmpty);
        expect(result.output, anyOf(contains('2013'), contains('2011')));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Web Fetch: fetches a URL content',
      () async {
        final agent = Agent(
          'anthropic',
          chatModelOptions: const AnthropicChatOptions(
            serverSideTools: {AnthropicServerSideTool.webFetch},
          ),
        );

        final result = await agent.send(
          'Fetch the content of https://example.com and summarize it.',
        );

        expect(result.output, isNotEmpty);
        expect(result.output.toLowerCase(), contains('domain'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
