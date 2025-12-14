#!/bin/bash
# SC-048: List models for default provider
echo "List default provider models:"
echo '$ dartantic models'
dart run bin/dartantic.dart models | head -20
