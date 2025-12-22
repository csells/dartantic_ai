// ignore_for_file: avoid_print, unreachable_from_main, avoid_dynamic_calls
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart';

void main() async {
  const model = 'gemini';
  await summarizeTextFile(model);
  await analyzeImages(model);
  await processTextWithImages(model);
  await multiModalConversation(model);
  await useLinkAttachment(model);
  await transcribeAudioText(model);
  await transcribeAudioJson(model);
  exit(0);
}

Future<void> summarizeTextFile(String model) async {
  final agent = Agent(model);
  print('\n${agent.displayName} Summarize Text File\n');

  const path = 'example/bin/files/bio.txt';
  final file = XFile.fromData(await File(path).readAsBytes(), path: path);

  await agent
      .sendStream(
        'Can you summarized the attached file?',
        attachments: [await DataPart.fromFile(file)],
        history: [ChatMessage.system('Be concise.')],
      )
      .forEach((r) => stdout.write(r.output));
  stdout.writeln();
}

Future<void> analyzeImages(String model) async {
  final agent = Agent(model);
  print('\n${agent.displayName} Analyze Multiple Images');

  const fridgePath = 'example/bin/files/fridge.png';
  final fridgeFile = XFile.fromData(
    await File(fridgePath).readAsBytes(),
    path: fridgePath,
  );

  const cupboardPath = 'example/bin/files/cupboard.png';
  final cupboardFile = XFile.fromData(
    await File(cupboardPath).readAsBytes(),
    path: cupboardPath,
  );

  await agent
      .sendStream(
        'I have two images from my kitchen. '
        'What meal could I make using items from both?',
        attachments: [
          await DataPart.fromFile(fridgeFile),
          await DataPart.fromFile(cupboardFile),
        ],
        history: [ChatMessage.system('Be concise.')],
      )
      .forEach((r) => stdout.write(r.output));
  stdout.writeln();
}

Future<void> processTextWithImages(String model) async {
  final agent = Agent(model);
  print('\n${agent.displayName} Combine Text File and Image Analysis');

  const bioPath = 'example/bin/files/bio.txt';
  final bioFile = XFile.fromData(
    await File(bioPath).readAsBytes(),
    path: bioPath,
  );

  const fridgePath = 'example/bin/files/fridge.png';
  final fridgeFile = XFile.fromData(
    await File(fridgePath).readAsBytes(),
    path: fridgePath,
  );

  await agent
      .sendStream(
        'What can you tell me about their lifestyle and dietary habits?',
        attachments: [
          await DataPart.fromFile(bioFile),
          await DataPart.fromFile(fridgeFile),
        ],
        history: [ChatMessage.system('Be concise.')],
      )
      .forEach((r) => stdout.write(r.output));
  stdout.writeln();
}

Future<void> multiModalConversation(String model) async {
  final agent = Agent(model);
  print('\n${agent.displayName} Multi-modal Conversation');

  const fridgePath = 'example/bin/files/fridge.png';
  final fridgeFile = XFile.fromData(
    await File(fridgePath).readAsBytes(),
    path: fridgePath,
  );

  final history = <ChatMessage>[ChatMessage.system('Be concise.')];

  // First turn: check the fridge
  await agent
      .sendStream(
        'What do you see in this fridge?',
        attachments: [await DataPart.fromFile(fridgeFile)],
        history: history,
      )
      .forEach((r) {
        stdout.write(r.output);
        history.addAll(r.messages);
      });

  // Second turn: follow-up question
  await agent
      .sendStream('Which items are the healthiest?', history: history)
      .forEach((r) {
        stdout.write(r.output);
        history.addAll(r.messages);
      });
  stdout.writeln('');
}

Future<void> useLinkAttachment(String model) async {
  final agent = Agent(model);
  print('\n${agent.displayName} Link Attachments');

  try {
    final imageLink = Uri.parse(
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg',
    );

    await agent
        .sendStream(
          'Can you describe this image?',
          attachments: [LinkPart(imageLink, mimeType: 'image/jpeg')],
          history: [ChatMessage.system('Be concise.')],
        )
        .forEach((r) => stdout.write(r.output));
    stdout.writeln();
  } on Exception catch (e) {
    print(
      'Error: $e\n'
      'NOTE: some providers require an upload to their associated servers '
      'before they can be used (e.g. google).',
    );
  }
}

Future<void> transcribeAudioText(String model) async {
  final agent = Agent(model);
  print('\n${agent.displayName} Transcribe Audio to Text');

  final audioBytes = await File(
    'example/bin/files/welcome-to-dartantic.mp3',
  ).readAsBytes();
  await agent
      .sendStream(
        'Transcribe this audio file word for word.',
        attachments: [
          DataPart(
            audioBytes,
            mimeType: 'audio/mp4',
            name: 'welcome-to-dartantic.mp3',
          ),
        ],
      )
      .forEach((r) => stdout.write(r.output));
  stdout.writeln();
}

Future<void> transcribeAudioJson(String model) async {
  final agent = Agent(model);
  print('\n${agent.displayName} Transcribe Audio with Timestamps (JSON)');

  final audioBytes = await File(
    'example/bin/files/welcome-to-dartantic.mp3',
  ).readAsBytes();
  final schema = JsonSchema.create({
    'type': 'object',
    'properties': {
      'transcript': {'type': 'string'},
      'words': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'word': {'type': 'string'},
            'start_time': {'type': 'number'},
            'end_time': {'type': 'number'},
          },
        },
      },
    },
  });

  // Stream JSON output
  final buffer = StringBuffer();
  await agent
      .sendStream(
        'Transcribe this audio file with word-level timestamps (in seconds).',
        outputSchema: schema,
        attachments: [
          DataPart(
            audioBytes,
            mimeType: 'audio/mp4',
            name: 'welcome-to-dartantic.mp3',
          ),
        ],
      )
      .forEach((r) {
        if (r.output.isNotEmpty) {
          buffer.write(r.output);
          stdout.write(r.output);
        }
      });
  stdout.writeln();

  // Parse complete JSON
  final completeJson = buffer.toString();
  final transcription = jsonDecode(completeJson) as Map<String, dynamic>;

  print('Transcript: ${transcription['transcript']}');
  print('\nWord-level timestamps:');

  final words = transcription['words'] as List;
  for (final word in words) {
    final w = word as Map<String, dynamic>;
    print(
      '  ${w['start_time']?.toStringAsFixed(2)}s - '
      '${w['end_time']?.toStringAsFixed(2)}s: ${w['word']}',
    );
  }
}
