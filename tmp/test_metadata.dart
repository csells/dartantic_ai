import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart'
    show ThinkingConfig, ThinkingConfigEnabledType;
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

void main() async {
  final agent = Agent(
    'anthropic:claude-sonnet-4-5',
    tools: [
      Tool(
        name: 'get_time',
        description: 'Get current time',
        inputSchema: {'type': 'object', 'properties': {}},
        function: (_) async => 'The current time is 3:45 PM',
      ),
    ],
    chatModelOptions: const AnthropicChatOptions(
      maxTokens: 16000,
      thinking: ThinkingConfig.enabled(
        type: ThinkingConfigEnabledType.enabled,
        budgetTokens: 10000,
      ),
    ),
  );

  print('Sending: What time is it?');
  await for (final chunk in agent.sendStream('What time is it?')) {
    if (chunk.metadata.containsKey('_anthropic_thinking_block')) {
      print('Found thinking block metadata in chunk!');
    }
  }

  print('\nConversation history:');
  for (final msg in agent.conversationHistory) {
    print(
      'Role: ${msg.role}, Parts: ${msg.parts.length}, '
      'Metadata keys: ${msg.metadata.keys.toList()}',
    );
  }
}
