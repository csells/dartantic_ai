# Server-Side Tools Examples

This example demonstrates the server-side tools available in the OpenAI Responses API through Dartantic.

## Running the Examples

```bash
# Show available demos
dart run example/bin/server_side_tools.dart

# Run a specific demo
dart run example/bin/server_side_tools.dart web_search
dart run example/bin/server_side_tools.dart image_gen
dart run example/bin/server_side_tools.dart code_interp
dart run example/bin/server_side_tools.dart file_search

# Run all demos in sequence
dart run example/bin/server_side_tools.dart all
```

## Available Server-Side Tools

### 1. Web Search (`web_search`)
Searches the web for current information. The model automatically formulates search queries and integrates results into its response.

**Example use cases:**
- Finding recent news or announcements
- Researching current events
- Getting up-to-date information beyond the model's training cutoff

### 2. Image Generation (`image_gen`)
Generates images from text descriptions using DALL-E. Returns images as base64-encoded data or URLs.

**Example use cases:**
- Creating logos and graphics
- Generating illustrations
- Producing visual content from descriptions

### 3. Code Interpreter (`code_interp`)
Executes Python code for data analysis, calculations, and visualizations.

**Example use cases:**
- Data analysis and statistics
- Creating charts and visualizations
- Complex calculations
- File processing

### 4. File Search (`file_search`)
Searches through files that have been uploaded to OpenAI. 

**Note:** This requires files to be pre-uploaded using the OpenAI Files API.

**Example use cases:**
- Searching documentation
- Finding specific information in uploaded PDFs
- Querying knowledge bases

## Metadata Observability

Each demo shows how to observe the tool execution through metadata events:

- **Progress tracking**: See when tools start, execute, and complete
- **Debugging**: View the actual queries, code, or parameters being used
- **Results handling**: Process returned data, images, or search results

## Implementation Details

The examples demonstrate:

1. **Tool-specific configuration**: Each tool can be enabled independently
2. **Metadata streaming**: Real-time updates as tools execute
3. **Result processing**: Handling different types of outputs (text, images, data)
4. **Error handling**: Graceful handling when tools aren't available or fail

## Requirements

- An OpenAI API key with access to the Responses API
- For file search: Pre-uploaded files to OpenAI
- For image generation: Appropriate usage limits for DALL-E

## Tips

- The model automatically decides when to use tools based on the prompt
- You can enable multiple tools and let the model choose
- Tool execution is transparent through metadata events
- Results are integrated directly into the model's response