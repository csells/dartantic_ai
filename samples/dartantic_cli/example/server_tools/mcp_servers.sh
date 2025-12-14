#!/bin/bash
# SC-029: MCP server configuration
# Note: Requires CONTEXT7_API_KEY environment variable
mkdir -p tmp
cat > tmp/mcp_settings.yaml << 'EOF'
agents:
  research:
    model: google
    mcp_servers:
      - name: context7
        url: https://mcp.context7.com/mcp
        headers:
          CONTEXT7_API_KEY: "${CONTEXT7_API_KEY}"
EOF

echo "Using MCP servers:"
echo '$ dartantic -s tmp/mcp_settings.yaml -a research -p "Hello"'
dart run bin/dartantic.dart -s tmp/mcp_settings.yaml -a research -p "Hello"
