#!/bin/bash
# SC-062: Environment variable substitution in settings
mkdir -p tmp
export TEST_TOKEN="my-secret-token"

cat > tmp/env_settings.yaml << 'EOF'
agents:
  test:
    model: google
    headers:
      Authorization: "Bearer ${TEST_TOKEN}"
EOF

echo "Settings with env var substitution:"
echo '$ TEST_TOKEN="my-secret-token" dartantic -s tmp/env_settings.yaml -a test -p "Hello"'
dart run bin/dartantic.dart -s tmp/env_settings.yaml -a test -p "Hello"
