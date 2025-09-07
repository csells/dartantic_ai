#!/bin/bash

# Test code interpreter with Chat Completions API (standard)
echo "Testing Chat Completions API with code_interpreter..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {
        "role": "user",
        "content": "Write Python code to calculate the first 10 Fibonacci numbers"
      }
    ]
  }' | python3 -m json.tool

echo ""
echo "---"
echo ""
echo "Testing Responses API with code_interpreter..."
echo ""

# Test with Responses API
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "X-OpenAI-Beta: responses" \
  -d '{
    "model": "gpt-4o",
    "stream": true,
    "input": [
      {
        "role": "user",
        "content": [
          {
            "type": "input_text",
            "text": "Calculate the first 10 Fibonacci numbers using Python"
          }
        ]
      }
    ],
    "tools": [
      {
        "type": "code_interpreter"
      }
    ]
  }'