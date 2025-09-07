# OpenAI API Endpoints Specification

## CRITICAL DISTINCTION - NEVER CONFUSE THESE TWO APIS

### 1. OpenAIChatModel - Chat Completions API
- **Endpoint**: `/v1/chat/completions`
- **Implementation**: Uses `openai_dart` package's `OpenAIClient.createChatCompletionStream`
- **Request Format**: Standard OpenAI Chat Completions format
  - `messages`: Array of message objects with `role` and `content`
  - `model`: Model name (e.g., "gpt-4o")
  - `tools`: Function definitions for tool calling
  - `stream`: Boolean for streaming
- **Response Format**: Standard chat completion deltas
- **Headers**: Standard authorization header only
- **Use Case**: General chat interactions, function calling

### 2. OpenAIResponsesChatModel - Responses API
- **Endpoint**: `/v1/responses` (NOT /v1/chat/completions!)
- **Implementation**: Custom HTTP client with SSE parsing
- **Request Format**: Responses API specific format
  - `instructions`: System-level instructions (NOT in messages array)
  - `input`: Array of input objects (NOT messages)
  - `model`: Model name
  - `tools`: Mix of function tools AND server-side tools
  - Stream is always enabled for this API
- **Response Format**: Server-sent events with specialized event types
- **Headers**: 
  - Standard authorization header
  - Accept: `text/event-stream`
  - NO beta header needed - this is a production API
- **Use Case**: Server-side tools (web search, image generation, file search, computer use, code interpreter)

## Server-Side Tools Support

### OpenAIChatModel
- ❌ Does NOT support server-side tools
- ✅ Supports function calling only
- ❌ Cannot use: web_search, image_generation, file_search, computer_use, code_interpreter

### OpenAIResponsesChatModel  
- ✅ FULL support for server-side tools
- ✅ Supports both function calling AND server-side tools
- ✅ Can use all of:
  - `web_search` - Internet search
  - `image_generation` - DALL-E image creation
  - `file_search` - Search uploaded documents
  - `computer_use` - Browser/desktop automation
  - `code_interpreter` - Python code execution in sandboxed containers

## Code Interpreter Specific Notes

### IMPORTANT: Code Interpreter ONLY works with Responses API
- The `/v1/chat/completions` endpoint does NOT support code_interpreter
- Only the `/v1/responses` endpoint supports code_interpreter
- Code interpreter requires `container: {"type": "auto"}` configuration
- OpenAI manages containers entirely server-side - we don't create or manage them

## Implementation Verification Checklist

### For OpenAIChatModel:
- [ ] Uses `openai_dart` package
- [ ] Calls `createChatCompletionStream` method
- [ ] NO custom HTTP implementation
- [ ] NO beta headers
- [ ] NO server-side tools

### For OpenAIResponsesChatModel:
- [ ] Uses custom HTTP client
- [ ] Endpoint URL ends with `/responses`
- [ ] NO beta header needed (production API)
- [ ] Converts messages to `instructions` + `input` format
- [ ] Handles SSE events for server-side tools
- [ ] Supports code_interpreter with container config

## Common Mistakes to AVOID

1. **NEVER** use `/v1/chat/completions` for OpenAIResponsesChatModel
2. **NEVER** try to add server-side tools to OpenAIChatModel
3. **NEVER** send messages array to Responses API - use instructions/input format
4. **NEVER** try to manage containers locally for code_interpreter - OpenAI handles it
5. **NEVER** confuse the two APIs - they are completely different!

## Testing Commands

### Test OpenAIChatModel (Chat Completions API):
```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### Test OpenAIResponsesChatModel (Responses API):
```bash
curl https://api.openai.com/v1/responses \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "instructions": "You are a helpful assistant",
    "input": "Hello",
    "tools": [{"type": "code_interpreter", "container": {"type": "auto"}}]
  }'
```

## File Locations

- **OpenAIChatModel**: `lib/src/chat_models/openai_chat/openai_chat_model.dart`
- **OpenAIResponsesChatModel**: `lib/src/chat_models/openai_responses/openai_responses_chat_model.dart`
- **Message Mappers**: 
  - Chat: `lib/src/chat_models/openai_chat/openai_message_mappers.dart`
  - Responses: `lib/src/chat_models/openai_responses/openai_responses_message_mappers.dart`

## Remember

The Responses API is a COMPLETELY DIFFERENT API from Chat Completions. They have:
- Different endpoints
- Different request formats
- Different response formats
- Different capabilities
- Different use cases

NEVER MIX THEM UP!