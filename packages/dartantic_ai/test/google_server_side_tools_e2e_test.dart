import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

void main() {
  group('Google server-side tooling E2E', () {
    test(
      'Code Execution: runs python code',
      () async {
        final agent = Agent(
          'google',
          chatModelOptions: const GoogleChatModelOptions(
            serverSideTools: {GoogleServerSideTool.codeExecution},
          ),
        );

        final result = await agent.send(
          'Use code execution to calculate 12345 * 67890 and print the result.',
        );

        expect(result.output.replaceAll(',', ''), contains('838102050'));
        // We might want to check metadata for code execution result if
        // possible,
        // but checking output is a good end-to-end verification.
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Google Search: searches and returns grounded results',
      () async {
        final agent = Agent(
          'google',
          chatModelOptions: const GoogleChatModelOptions(
            serverSideTools: {GoogleServerSideTool.googleSearch},
          ),
        );

        final result = await agent.send(
          'Search for "Dart programming language release date" and tell me '
          'the year.',
        );

        expect(result.output, contains('2011')); // Or 2013
        expect(result.output, contains('Dart'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
