import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_event_mapper.dart';
import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_message_mapper.dart';
import 'package:dartantic_ai/src/shared/openai_responses_metadata.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart' as openai;
import 'package:test/test.dart';

// Mock download function for tests
Future<ContainerFileData> _mockDownloadContainerFile(
  String containerId,
  String fileId,
) async => ContainerFileData(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  fileName: '$fileId.bin',
);

void main() {
  group('OpenAIResponsesEventMapper', () {
    test('streams text deltas as chat results', () async {
      final mapper = OpenAIResponsesEventMapper(
        modelName: 'gpt-4o',
        storeSession: true,
        history: const OpenAIResponsesHistorySegment(
          items: [],
          input: null,
          instructions: null,
          previousResponseId: null,
          anchorIndex: -1,
        ),
        downloadContainerFile: _mockDownloadContainerFile,
      );

      final results = await mapper
          .handle(
            const openai.ResponseOutputTextDelta(
              itemId: 'msg',
              outputIndex: 0,
              contentIndex: 0,
              delta: 'Hello',
              sequenceNumber: 1,
            ),
          )
          .toList();

      expect(results, hasLength(1));
      final chunk = results.single;
      expect(
        chunk.output.parts.single,
        isA<TextPart>().having((p) => p.text, 'text', 'Hello'),
      );
    });

    test(
      'builds final chat result with telemetry and session metadata',
      () async {
        const history = OpenAIResponsesHistorySegment(
          items: [],
          input: null,
          instructions: null,
          previousResponseId: 'resp_prev',
          anchorIndex: 1,
        );

        final mapper = OpenAIResponsesEventMapper(
          modelName: openai.ChatModel.gpt4o.value,
          storeSession: true,
          history: history,
          downloadContainerFile: _mockDownloadContainerFile,
        );

        final response = openai.Response(
          id: 'resp_123',
          model: openai.ChatModel.gpt4o,
          status: 'completed',
          usage: const openai.Usage(
            inputTokens: 12,
            outputTokens: 34,
            totalTokens: 46,
          ),
          output: [
            const openai.OutputMessage(
              role: 'assistant',
              content: [
                openai.OutputTextContent(text: 'Hello!', annotations: []),
              ],
              id: 'msg-1',
              status: 'completed',
            ),
            openai.FunctionCall(
              callId: 'tool-1',
              name: 'fetchData',
              arguments: jsonEncode({'foo': 'bar'}),
            ),
            openai.FunctionCallOutput(
              callId: 'tool-1',
              output: jsonEncode({'result': 42}),
            ),
            const openai.Reasoning(
              id: 'reason-1',
              summary: [openai.ReasoningSummary(text: 'Thinking...')],
            ),
            const openai.CodeInterpreterCall(
              id: 'ci-1',
              code: 'print(1)',
              status: openai.CodeInterpreterToolCallStatus.completed,
              containerId: 'container-7',
              results: [openai.CodeInterpreterLogs('done')],
            ),
            openai.ImageGenerationCall(
              id: 'img-1',
              status: openai.ImageGenerationCallStatus.completed,
              resultBase64: base64Encode(utf8.encode('fake')), // any bytes
            ),
            const openai.WebSearchCall(
              id: 'search-1',
              status: openai.WebSearchToolCallStatus.completed,
            ),
            const openai.FileSearchCall(
              id: 'files-1',
              status: openai.FileSearchToolCallStatus.completed,
              queries: ['query'],
              results: [
                openai.FileSearchToolCallResult(
                  text: 'snippet',
                  fileId: 'file-1',
                ),
              ],
            ),
            const openai.McpCall(
              id: 'mcp-1',
              name: 'list',
              arguments: '{}',
              serverLabel: 'server-a',
              output: 'ok',
            ),
            const openai.McpApprovalRequest(
              id: 'approve-1',
              arguments: '{}',
              name: 'needs_approval',
              serverLabel: 'server-a',
            ),
            const openai.McpApprovalResponse(
              approvalRequestId: 'approve-1',
              approve: true,
              reason: 'All good',
            ),
          ],
        );

        final results = await mapper
            .handle(
              openai.ResponseCompleted(response: response, sequenceNumber: 10),
            )
            .toList();

        expect(results, hasLength(1));
        final result = results.single;

        expect(result.id, equals('resp_123'));
        expect(result.usage.promptTokens, equals(12));
        expect(result.usage.responseTokens, equals(34));

        final message = result.output;
        expect(
          message.parts.whereType<TextPart>().single.text,
          equals('Hello!'),
        );

        final callPart = message.parts.whereType<ToolPart>().firstWhere(
          (part) => part.kind == ToolPartKind.call,
        );
        expect(callPart.name, equals('fetchData'));

        final resultPart = message.parts.whereType<ToolPart>().firstWhere(
          (part) => part.kind == ToolPartKind.result,
        );
        expect(resultPart.result, containsPair('result', 42));

        final session = OpenAIResponsesMetadata.getSessionData(
          message.metadata,
        )!;
        expect(
          session[OpenAIResponsesMetadata.responseIdKey],
          equals('resp_123'),
        );

        // Message metadata should ONLY contain session info Tool events are not
        // duplicated on the message (only in streaming metadata)
        expect(
          message.metadata.keys.toSet(),
          equals({'_responses_session'}),
          reason: 'Message metadata should only contain session info',
        );

        expect(result.metadata['response_id'], equals('resp_123'));
        expect(result.metadata['status'], equals('completed'));
      },
    );

    test(
      'handles streaming image generation with ResponseOutputItemDone',
      () async {
        final mapper = OpenAIResponsesEventMapper(
          modelName: 'gpt-4o',
          storeSession: false,
          history: const OpenAIResponsesHistorySegment(
            items: [],
            input: null,
            instructions: null,
            previousResponseId: null,
            anchorIndex: -1,
          ),
          downloadContainerFile: _mockDownloadContainerFile,
        );

        // Step 1: ResponseOutputItemAdded with ImageGenerationCall
        var results = await mapper
            .handle(
              const openai.ResponseOutputItemAdded(
                outputIndex: 0,
                sequenceNumber: 1,
                item: openai.ImageGenerationCall(
                  id: 'img-1',
                  status: openai.ImageGenerationCallStatus.inProgress,
                ),
              ),
            )
            .toList();
        expect(results, isEmpty); // No output yet

        // Step 2: ResponseImageGenerationCallInProgress
        results = await mapper
            .handle(
              const openai.ResponseImageGenerationCallInProgress(
                itemId: 'img-1',
                outputIndex: 0,
                sequenceNumber: 2,
              ),
            )
            .toList();
        expect(results, hasLength(1)); // Metadata chunk emitted
        expect(results.first.metadata['image_generation'], isNotNull);

        // Step 3: ResponseImageGenerationCallGenerating
        results = await mapper
            .handle(
              const openai.ResponseImageGenerationCallGenerating(
                itemId: 'img-1',
                outputIndex: 0,
                sequenceNumber: 3,
              ),
            )
            .toList();
        expect(results, hasLength(1)); // Metadata chunk emitted

        // Step 4: ResponseImageGenerationCallPartialImage
        const fakeImageData =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC'
            '0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
        results = await mapper
            .handle(
              const openai.ResponseImageGenerationCallPartialImage(
                itemId: 'img-1',
                outputIndex: 0,
                sequenceNumber: 4,
                partialImageB64: fakeImageData,
                partialImageIndex: 0,
              ),
            )
            .toList();
        expect(results, hasLength(1)); // Metadata chunk emitted

        // Step 5: ResponseOutputItemDone marks completion
        results = await mapper
            .handle(
              const openai.ResponseOutputItemDone(
                outputIndex: 0,
                sequenceNumber: 5,
                item: openai.ImageGenerationCall(
                  id: 'img-1',
                  status: openai.ImageGenerationCallStatus.completed,
                  resultBase64: fakeImageData,
                ),
              ),
            )
            .toList();
        expect(results, isEmpty); // Just marks completion, no output yet

        // Step 6: ResponseCompleted should include the image as a DataPart
        const response = openai.Response(
          id: 'resp_img',
          model: openai.ChatModel.gpt4o,
          status: 'completed',
          output: [
            openai.ImageGenerationCall(
              id: 'img-1',
              status: openai.ImageGenerationCallStatus.completed,
              resultBase64: fakeImageData,
            ),
          ],
        );

        results = await mapper
            .handle(
              const openai.ResponseCompleted(
                response: response,
                sequenceNumber: 6,
              ),
            )
            .toList();

        expect(results, hasLength(1));
        final finalResult = results.single;
        final message = finalResult.output;

        // Verify the image was added as a DataPart
        final dataParts = message.parts.whereType<DataPart>().toList();
        expect(dataParts, hasLength(1));
        expect(dataParts.first.mimeType, equals('image/png'));
        expect(dataParts.first.bytes, equals(base64Decode(fakeImageData)));
        expect(dataParts.first.name, equals('image_0.png'));
      },
    );

    test('attaches container file citations with inferred metadata', () async {
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC'
          '0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
      final pngBytes = base64Decode(pngBase64);

      final mapper = OpenAIResponsesEventMapper(
        modelName: 'gpt-4o',
        storeSession: false,
        history: const OpenAIResponsesHistorySegment(
          items: [],
          input: null,
          instructions: null,
          previousResponseId: null,
          anchorIndex: -1,
        ),
        downloadContainerFile: (containerId, fileId) async => ContainerFileData(
          bytes: Uint8List.fromList(pngBytes),
          fileName: 'plot.png',
        ),
      );

      const response = openai.Response(
        id: 'resp_file',
        model: openai.ChatModel.gpt4o,
        status: 'completed',
        output: [
          openai.OutputMessage(
            role: 'assistant',
            content: [
              openai.OutputTextContent(
                text: 'See plot',
                annotations: [
                  openai.ContainerFileCitation(
                    containerId: 'container-1',
                    fileId: 'file-1',
                    startIndex: 0,
                    endIndex: 4,
                  ),
                ],
              ),
            ],
            id: 'msg-plot',
            status: 'completed',
          ),
        ],
      );

      final results = await mapper
          .handle(
            const openai.ResponseCompleted(
              response: response,
              sequenceNumber: 1,
            ),
          )
          .toList();

      expect(results, hasLength(1));
      final message = results.single.output;
      final attachment = message.parts.whereType<DataPart>().single;
      expect(attachment.mimeType, 'image/png');
      expect(attachment.name, 'plot.png');
      expect(attachment.bytes, equals(pngBytes));
    });
  });
}
