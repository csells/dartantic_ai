import 'dart:convert';

import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_message_mapper.dart';
import 'package:dartantic_ai/src/shared/openai_responses_metadata.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart' as openai;
import 'package:test/test.dart';

void main() {
  group('OpenAIResponsesMessageMapper', () {
    test('maps system and multimodal user messages into response items', () {
      final messages = [
        ChatMessage.system('You are helpful.'),
        ChatMessage.user(
          'Describe the image.',
          parts: [
            DataPart(
              utf8.encode('image-bytes'),
              mimeType: 'image/png',
              name: 'sample.png',
            ),
          ],
        ),
      ];

      final segment = OpenAIResponsesMessageMapper.mapHistory(messages);

      expect(segment.previousResponseId, isNull);
      expect(segment.instructions, equals('You are helpful.'));
      expect(segment.input, isA<openai.ResponseInputItems>());

      final input = segment.input as openai.ResponseInputItems?;
      expect(input, isNotNull);
      expect(input!.items, hasLength(1));

      final messageItem = input.items.first as openai.InputMessage;
      expect(messageItem.role, equals('user'));
      expect(messageItem.content, hasLength(2));
      expect(
        messageItem.content.first,
        isA<openai.InputTextContent>().having(
          (c) => c.text,
          'text',
          equals('Describe the image.'),
        ),
      );
      expect(
        messageItem.content.last,
        isA<openai.InputImageContent>().having(
          (c) => c.imageUrl,
          'imageUrl',
          startsWith('data:image/png;base64,'),
        ),
      );
    });

    test('respects session metadata when resuming conversations', () {
      final sessionMetadata = {
        OpenAIResponsesMetadata.sessionKey: {
          OpenAIResponsesMetadata.responseIdKey: 'resp_123',
          OpenAIResponsesMetadata.pendingItemsKey: [
            {
              'type': 'function_call_output',
              'call_id': 'tool-1',
              'output': jsonEncode({'status': 'ok'}),
            },
          ],
        },
      };

      final messages = [
        ChatMessage.system('Initial instructions'),
        ChatMessage.user('First user turn'),
        ChatMessage.model('', metadata: sessionMetadata),
        ChatMessage.user(
          '',
          parts: const [
            ToolPart.result(
              id: 'tool-1',
              name: 'fetchData',
              result: {'value': 42},
            ),
          ],
        ),
      ];

      final segment = OpenAIResponsesMessageMapper.mapHistory(messages);

      expect(segment.instructions, isNull);
      expect(segment.previousResponseId, equals('resp_123'));

      final input = segment.input as openai.ResponseInputItems?;
      expect(input, isNotNull);
      expect(input!.items, hasLength(2));

      expect(input.items.first, isA<openai.FunctionCallOutput>());
      expect(input.items.last, isA<openai.FunctionCallOutput>());

      final first = input.items.first as openai.FunctionCallOutput;
      expect(first.callId, equals('tool-1'));

      final second = input.items.last as openai.FunctionCallOutput;
      expect(second.callId, equals('tool-1'));
      expect(
        jsonDecode(second.output) as Map<String, dynamic>,
        containsPair('value', 42),
      );
    });
  });
}
