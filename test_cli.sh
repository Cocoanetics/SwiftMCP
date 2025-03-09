#!/bin/bash

# Build the project
echo "Building project..."
swift build

# Test one-off mode with divide tool
echo "Testing one-off mode with divide tool..."
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": "10"}}}' | ./.build/debug/SwiftMCPDemo

# Test one-off mode with add tool
echo "Testing one-off mode with add tool..."
echo '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "add", "arguments": {"a": "5", "b": "7"}}}' | ./.build/debug/SwiftMCPDemo

# Test one-off mode with verbose flag
echo "Testing one-off mode with verbose flag..."
echo '{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "multiply", "arguments": {"a": "6", "b": "8"}}}' | ./.build/debug/SwiftMCPDemo -v

# Make the script executable
chmod +x test_cli.sh 