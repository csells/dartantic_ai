#!/bin/bash
# SC-051: List models for agent from settings
mkdir -p tmp
cat > tmp/agent_models.yaml << 'EOF'
agents:
  myagent:
    model: anthropic
EOF

echo "List models for agent:"
echo '$ dartantic -s tmp/agent_models.yaml -a myagent models'
dart run bin/dartantic.dart -s tmp/agent_models.yaml -a myagent models | head -20
