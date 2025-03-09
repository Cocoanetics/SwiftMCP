#!/bin/bash

# Build the project
swift build || { echo "Build failed"; exit 1; }

# Test the divide function with integer parameters
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": 4, "denominator": 2}, "_meta": {"progressToken": 1}}, "id": 1}' | .build/debug/SwiftMCPDemo 