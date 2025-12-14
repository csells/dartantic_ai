#!/bin/bash
# SC-031: Selectively disable specific server tools
echo "Selectively disable server tools:"
echo '$ dartantic --no-server-tool=web_search -a anthropic -p "Hello"'
dart run bin/dartantic.dart --no-server-tool=web_search -a anthropic -p "Hello"
