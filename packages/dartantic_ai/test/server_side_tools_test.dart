import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_message_mappers.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

void main() {
  group('Server-side tools wiring', () {
    test('provider passes options to model defaultOptions', () async {
      final provider = OpenAIResponsesProvider(apiKey: 'test-key');

      const options = OpenAIResponsesChatOptions(
        serverSideTools: {
          OpenAIServerSideTool.webSearch,
          OpenAIServerSideTool.fileSearch,
        },
        fileSearchConfig: FileSearchConfig(maxResults: 3),
        webSearchConfig: WebSearchConfig(siteFilter: 'site:openai.com'),
        cacheConfig: OpenAICacheConfig(
          enabled: true,
          sessionId: 'sess-1',
          ttlSeconds: 60,
        ),
      );

      final model = provider.createChatModel(name: 'gpt-4o', options: options);

      final defaults = model.defaultOptions;

      expect(defaults.serverSideTools, isNotNull);
      expect(
        defaults.serverSideTools,
        contains(OpenAIServerSideTool.webSearch),
      );
      expect(
        defaults.serverSideTools,
        contains(OpenAIServerSideTool.fileSearch),
      );
      expect(defaults.fileSearchConfig?.maxResults, equals(3));
      expect(defaults.webSearchConfig?.siteFilter, equals('site:openai.com'));
      expect(defaults.cacheConfig?.enabled, isTrue);
      expect(defaults.cacheConfig?.sessionId, equals('sess-1'));
      expect(defaults.cacheConfig?.ttlSeconds, equals(60));
    });

    test('request tools array includes built-ins with config', () {
      const defaults = OpenAIResponsesChatOptions(
        serverSideTools: {
          OpenAIServerSideTool.webSearch,
          OpenAIServerSideTool.fileSearch,
        },
        fileSearchConfig: FileSearchConfig(maxResults: 5),
        webSearchConfig: WebSearchConfig(timeRange: 'past_week'),
      );

      final messages = <ChatMessage>[ChatMessage.user('hello')];

      final request = buildResponsesRequest(
        messages,
        modelName: 'gpt-4o',
        defaultOptions: defaults,
        tools: const <Tool>[],
        temperature: 0.2,
      );

      final toolsArray = request['tools'] as List?;
      expect(toolsArray, isNotNull);

      // Expect web_search and file_search entries
      final toolTypes = toolsArray!
          .map((e) => (e as Map)['type'])
          .cast<String>()
          .toSet();
      expect(toolTypes.contains('web_search'), isTrue);
      expect(toolTypes.contains('file_search'), isTrue);

      // Validate config objects merged
      final fileSearch =
          toolsArray.where((e) => (e as Map)['type'] == 'file_search').first
              as Map;
      expect((fileSearch['config'] as Map)['max_results'], equals(5));

      final webSearch =
          toolsArray.where((e) => (e as Map)['type'] == 'web_search').first
              as Map;
      expect((webSearch['config'] as Map)['time_range'], equals('past_week'));
    });
  });
}
