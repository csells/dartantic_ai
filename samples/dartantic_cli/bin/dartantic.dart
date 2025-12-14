import 'dart:io';

import 'package:dartantic_cli/src/runner.dart';

Future<void> main(List<String> args) async {
  final runner = DartanticCommandRunner();
  final exitCode = await runner.run(args);
  exit(exitCode);
}
