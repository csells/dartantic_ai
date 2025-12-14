#!/bin/bash
# SC-030: Custom provider configuration
mkdir -p tmp
cat > tmp/custom_provider.yaml << 'EOF'
agents:
  custom-openai:
    model: openai:gpt-4o-mini
    base_url: https://api.openai.com/v1
    headers:
      X-Custom-Header: "custom-value"
EOF

echo "Using custom provider config:"
echo '$ dartantic -s tmp/custom_provider.yaml -a custom-openai -p "Hello"'
dart run bin/dartantic.dart -s tmp/custom_provider.yaml -a custom-openai -p "Hello"
