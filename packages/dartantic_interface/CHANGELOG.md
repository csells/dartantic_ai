## 2.0.0

- **BREAKING**: Removed `ProviderCaps` enum from the interface. Provider
  capabilities were only meaningful for testing default models and provided no
  provider-wide guarantees. Capability filtering for tests is now handled via
  `ProviderTestCaps` in `dartantic_ai`'s test infrastructure. Consider the
  `Provider.listModels` method for run-time model details, e.g. chat, embedding,
  media, etc.
- Removed `caps` field from `Provider` base class.

## 1.3.0

- introduced media generation primitives (`MediaGenerationModel`,
  `MediaGenerationResult`, `MediaGenerationModelResult`, and
  `MediaGenerationModelOptions`)
- extended `Provider` with media factory support and added
  `ProviderCaps.mediaGeneration`
- added `ModelKind.media` for provider defaults and discovery

## 1.2.0

- added optional 'thinking' field to ChatResult for enhanced reasoning output
- updated Provider to support thinking feature toggle

## 1.1.0

- ProviderCaps.vision => ProviderCaps.chatVision to tighten the meaning

## 1.0.5

- made usage nullable for when there is no usage.

## 1.0.4

- added `ProviderCaps.thinking`

## 1.0.3

- remove custom lint dependency

## 1.0.2

- fixed a compilation error on the web

## 1.0.1

- downgrading meta for wider compatibility

## 1.0.0

- initial release
