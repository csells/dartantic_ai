#!/bin/bash
# SC-050: List models using provider alias
echo "List models using alias (gemini -> google):"
echo '$ dartantic -a gemini models'
dart run bin/dartantic.dart -a gemini models | head -20
