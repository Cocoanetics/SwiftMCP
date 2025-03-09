#!/bin/bash

# Build the project
echo "Building project..."
swift build

# Instructions for manual testing
echo "To test the continuous mode, run the following command in one terminal:"
echo "./.build/debug/SwiftMCPDemo --continuous --verbose"
echo ""
echo "Then, in another terminal, you can send JSON-RPC requests like this:"
echo "echo '{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"tools/call\", \"params\": {\"name\": \"divide\", \"arguments\": {\"numerator\": \"10\"}}}' > /dev/stdin"
echo ""
echo "Or you can use a named pipe for more reliable communication:"
echo ""
echo "# In terminal 1 (create a named pipe and start the server):"
echo "mkfifo /tmp/mcp_pipe"
echo "cat /tmp/mcp_pipe | ./.build/debug/SwiftMCPDemo --continuous --verbose"
echo ""
echo "# In terminal 2 (send requests to the pipe):"
echo "echo '{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"tools/call\", \"params\": {\"name\": \"divide\", \"arguments\": {\"numerator\": \"10\"}}}' > /tmp/mcp_pipe"
echo ""
echo "The server will process each request and continue running indefinitely."
echo "Press Ctrl+C to stop the server when you're done testing." 