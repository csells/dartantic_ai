// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

void main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    print('OPENAI_API_KEY environment variable not set');
    exit(1);
  }

  print('=== Debug Raw Events from Responses API ===\n');

  final request = {
    "model": "o1",
    "input": [
      {
        "role": "user",
        "content": [
          {"type": "input_text", "text": "What is the weather in Boston?"}
        ]
      }
    ],
    "tools": [
      {
        "type": "function",
        "name": "weather",
        "description": "Get weather for a location",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {"type": "string"}
          },
          "required": ["location"]
        }
      }
    ],
    "stream": true
  };

  try {
    final httpRequest = http.Request(
      'POST',
      Uri.parse('https://api.openai.com/v1/responses'),
    );
    httpRequest.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    });
    httpRequest.body = json.encode(request);

    final response = await httpRequest.send();
    print('Status: ${response.statusCode}');

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      print('Error response: $body');
      exit(1);
    }

    // Process streaming response
    await response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
      if (line.trim().isEmpty || !line.startsWith('data: ')) return;
      
      final dataLine = line.substring(6);
      if (dataLine == '[DONE]') {
        print('=== DONE ===');
        return;
      }

      try {
        final data = json.decode(dataLine) as Map<String, dynamic>;
        final eventType = data['object']?.toString() ?? 'unknown';
        
        print('\n--- Event: $eventType ---');
        print('Raw data: ${json.encode(data)}');
        
        // Look specifically for response ID
        if (data.containsKey('response')) {
          print('Found response field: ${json.encode(data['response'])}');
        }
        if (data.containsKey('id')) {
          print('Found id field: ${data['id']}');
        }
        
      } catch (e) {
        print('Failed to parse JSON: $e');
        print('Raw line: $dataLine');
      }
    });

  } catch (e) {
    print('Error: $e');
    exit(1);
  }

  exit(0);
}