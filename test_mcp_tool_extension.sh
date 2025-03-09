#!/bin/bash

# Build the project
swift build

# Run the demo with a divide operation that uses the default value for denominator
echo "Testing divide with default value..."
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": "10"}}}' | ./.build/debug/SwiftMCPDemo

echo ""
echo "Done!" 