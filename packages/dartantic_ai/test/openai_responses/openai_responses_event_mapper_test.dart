import 'dart:convert';

import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_event_mapper.dart';
import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_message_mapper.dart';
import 'package:dartantic_ai/src/shared/openai_responses_metadata.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart' as openai;
import 'package:test/test.dart';

void main() {
  group('OpenAIResponsesEventMapper', () {
    test('streams text deltas as chat results', () {
      final mapper = OpenAIResponsesEventMapper(
        modelName: 'gpt-4o',
        storeSession: true,
        history: const OpenAIResponsesHistorySegment(
          items: [],
          input: null,
          instructions: null,
          previousResponseId: null,
          anchorIndex: -1,
          pendingItems: [],
        ),
      );

      final results = mapper
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

    test('builds final chat result with telemetry and session metadata', () {
      const history = OpenAIResponsesHistorySegment(
        items: [],
        input: null,
        instructions: null,
        previousResponseId: 'resp_prev',
        anchorIndex: 1,
        pendingItems: [],
      );

      final mapper = OpenAIResponsesEventMapper(
        modelName: openai.ChatModel.gpt4o.value,
        storeSession: true,
        history: history,
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
            argumentsJson: '{}',
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

      final results = mapper
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
      expect(message.parts.whereType<TextPart>().single.text, equals('Hello!'));

      final callPart = message.parts.whereType<ToolPart>().firstWhere(
        (part) => part.kind == ToolPartKind.call,
      );
      expect(callPart.name, equals('fetchData'));

      final resultPart = message.parts.whereType<ToolPart>().firstWhere(
        (part) => part.kind == ToolPartKind.result,
      );
      expect(resultPart.result, containsPair('result', 42));

      final session = OpenAIResponsesMetadata.getSessionData(message.metadata)!;
      expect(
        session[OpenAIResponsesMetadata.responseIdKey],
        equals('resp_123'),
      );

      expect(message.metadata['thinking'], contains('Thinking'));

      final codeInterpreter =
          (message.metadata['code_interpreter'] as Map<String, Object?>?) ?? {};
      expect(codeInterpreter['calls'], isNotEmpty);

      final imageGeneration =
          (message.metadata['image_generation'] as Map<String, Object?>?) ?? {};
      expect(imageGeneration['calls'], isNotEmpty);

      final mcp = (message.metadata['mcp'] as Map<String, Object?>?) ?? {};
      expect(mcp['entries'], isNotEmpty);

      expect(result.metadata['response_id'], equals('resp_123'));
      expect(result.metadata['status'], equals('completed'));
    });
  });
}
