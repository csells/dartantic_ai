import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_server_side_tool_mapper.dart';
import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_server_side_tools.dart';
import 'package:openai_core/openai_core.dart' as openai;
import 'package:test/test.dart';

void main() {
  group('OpenAIResponsesServerSideToolMapper.buildServerSideTools', () {
    test('builds web search tool with location hints', () {
      final tools = OpenAIResponsesServerSideToolMapper.buildServerSideTools(
        serverSideTools: const {OpenAIServerSideTool.webSearch},
        webSearchConfig: const WebSearchConfig(
          contextSize: WebSearchContextSize.high,
          location: WebSearchLocation(city: 'Berlin', country: 'DE'),
        ),
      );

      expect(tools, hasLength(1));
      final tool = tools.single as openai.WebSearchPreviewTool;
      expect(tool.searchContextSize, openai.SearchContextSize.high);
      expect(tool.userLocation?.city, 'Berlin');
      expect(tool.userLocation?.country, 'DE');
    });

    test('skips file search when vector stores missing', () {
      final tools = OpenAIResponsesServerSideToolMapper.buildServerSideTools(
        serverSideTools: const {OpenAIServerSideTool.fileSearch},
        fileSearchConfig: const FileSearchConfig(),
      );

      expect(tools, isEmpty);
    });

    test('builds file search tool when vector stores provided', () {
      final tools = OpenAIResponsesServerSideToolMapper.buildServerSideTools(
        serverSideTools: const {OpenAIServerSideTool.fileSearch},
        fileSearchConfig: const FileSearchConfig(
          vectorStoreIds: ['vs_123'],
          maxResults: 5,
          ranker: 'default',
          scoreThreshold: 0.42,
        ),
      );

      expect(tools, hasLength(1));
      final tool = tools.single as openai.FileSearchTool;
      expect(tool.vectorStoreIds, ['vs_123']);
      expect(tool.maxNumResults, 5);
      expect(tool.rankingOptions?.ranker, 'default');
      expect(tool.rankingOptions?.scoreThreshold, 0.42);
    });

    test('builds code interpreter tool with container reuse', () {
      final tools = OpenAIResponsesServerSideToolMapper.buildServerSideTools(
        serverSideTools: const {OpenAIServerSideTool.codeInterpreter},
        codeInterpreterConfig: const CodeInterpreterConfig(
          containerId: 'ctr_abc',
          fileIds: ['file1', 'file2'],
        ),
      );

      expect(tools, hasLength(1));
      final tool = tools.single as openai.CodeInterpreterTool;
      expect(tool.container, isA<openai.CodeInterpreterContainerId>());
      final container = tool.container as openai.CodeInterpreterContainerId;
      expect(container.containerId, 'ctr_abc');
    });

    test('builds image generation tool', () {
      final tools = OpenAIResponsesServerSideToolMapper.buildServerSideTools(
        serverSideTools: const {OpenAIServerSideTool.imageGeneration},
      );

      expect(tools.single, isA<openai.ImageGenerationTool>());
    });
  });
}
