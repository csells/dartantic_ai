#!/bin/bash
# SC-023: Disable thinking via CLI flag
echo "Disabling thinking mode:"
echo '$ dartantic -a google:gemini-2.5-flash --no-thinking -p "What is 2+2?"'
dart run bin/dartantic.dart -a google:gemini-2.5-flash --no-thinking -p "What is 2+2?"
