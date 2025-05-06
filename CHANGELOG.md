## 0.2.0

- Define tools and their inputs/outputs easily
- Automatically generate LLM-specific tool/output schemas
- Allow for a model descriptor string that just contains a family name so
  that the provider can choose the default model.

## 0.1.0

- Multi-Model Support (just Gemini and OpenAI models so far)
- Create agents from model strings (e.g. `openai:gpt-4o`) or typed
  providers (e.g. `GoogleProvider()`)
- Automatically check environment for API key if none is provided (not web
  compatible)
- String output via `Agent.run`
- Typed output via `Agent.runFor`

## 0.0.1

- Initial version.
