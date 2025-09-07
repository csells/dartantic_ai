#!/bin/bash

echo "Testing Responses API with correct input format..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test with the input array format the Responses API expects
curl -X POST https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "X-OpenAI-Beta: responses" \
  -d '{
    "model": "gpt-4o",
    "stream": false,
    "input": [
      {
        "role": "user",
        "content": [
          {
            "type": "input_text",
            "text": "What is 2+2?"
          }
        ]
      }
    ]
  }' | python3 -m json.tool