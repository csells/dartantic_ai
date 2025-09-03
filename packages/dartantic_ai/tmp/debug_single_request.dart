// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

void main() async {
  final apiKey = const String.fromEnvironment('OPENAI_API_KEY');
  if (apiKey.isEmpty) {
    print('OPENAI_API_KEY environment variable not set');
    exit(1);
  }

  print('=== Testing single request with tool calls and results ===\n');

  final request = {
    "model": "o1",
    "input": [
      {
        "role": "user",
        "content": [
          {"type": "input_text", "text": "What is the weather in Boston?"}
        ]
      },
      {
        "role": "assistant", 
        "content": [
          {"type": "output_text", "text": "I'll check the weather for you."},
          // Include tool call in the same request
        ]
      },
      {
        "type": "function_call_output",
        "call_id": "call_test123",
        "output": '{"temperature": 25, "conditions": "sunny"}'
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
    "stream": false
  };

  try {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: json.encode(request),
    );

    print('Status: ${response.statusCode}');
    print('Response: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }

  exit(0);
}