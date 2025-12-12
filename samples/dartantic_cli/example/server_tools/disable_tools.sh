#!/bin/bash
# SC-026/SC-027: Disable server-side tools
echo "Disabling specific server-side tool:"
echo '$ dartantic -a anthropic --no-server-tool webSearch -p "Hello"'
dart run bin/dartantic.dart -a anthropic --no-server-tool webSearch -p "Say hello."

echo ""
echo "Disabling multiple server-side tools:"
echo '$ dartantic -a anthropic --no-server-tool webSearch,codeInterpreter -p "Hello"'
dart run bin/dartantic.dart -a anthropic --no-server-tool webSearch,codeInterpreter -p "Say hello again."
