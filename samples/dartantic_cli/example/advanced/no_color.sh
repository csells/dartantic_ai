#!/bin/bash
# SC-034: Disable colored output
echo "Disabling colored output:"
echo '$ dartantic --no-color -p "Hello"'
dart run bin/dartantic.dart --no-color -p "Hello"
