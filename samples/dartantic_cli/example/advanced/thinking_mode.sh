#!/bin/bash
# SC-022: See model's reasoning process
echo "Thinking mode (shows reasoning with Gemini):"
echo '$ dartantic -a google:gemini-2.5-flash -p "Think step by step: what is 15 * 23?"'
dart run bin/dartantic.dart -a google:gemini-2.5-flash -p "Think step by step: what is 15 * 23?"
