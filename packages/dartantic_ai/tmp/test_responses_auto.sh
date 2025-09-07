#!/bin/bash

echo "Testing Responses API with code_interpreter and auto container..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test with the exact format from the screenshot
curl -X POST https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "X-OpenAI-Beta: responses" \
  -d '{
    "model": "gpt-4",
    "stream": true,
    "messages": [
      {
        "role": "system",
        "content": "You are a personal math tutor. When asked a math question, write and run code using the python tool to answer the question."
      },
      {
        "role": "user",
        "content": "I need to solve the equation 3x + 11 = 14. Can you help me?"
      }
    ],
    "tools": [
      {
        "type": "code_interpreter",
        "container": {
          "type": "auto"
        }
      }
    ]
  }'