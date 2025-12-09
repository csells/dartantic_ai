// ignore_for_file: avoid_print

import 'package:dartantic_ai/dartantic_ai.dart';

void main() {
  assert(
    Agent.getProvider('anthropic').defaultModelNames[ModelKind.chat] ==
        'claude-sonnet-4-0',
  );

  // all four of these resolve to the same model
  const model1 = 'anthropic';
  const model2 = 'anthropic:claude-sonnet-4-0';
  const model3 = 'anthropic/claude-sonnet-4-0';
  const model4 = 'anthropic?chat=claude-sonnet-4-0';

  final agent1 = Agent(model1);
  final agent2 = Agent(model2);
  final agent3 = Agent(model3);
  final agent4 = Agent(model4);

  assert(agent1.model == agent2.model);
  assert(agent2.model == agent3.model);
  assert(agent3.model == agent4.model);

  print('All of these successfully resolved to the same model:');
  print(model1);
  print(model2);
  print(model3);
  print(model4);
}
