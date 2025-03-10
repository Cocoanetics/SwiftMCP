#!/bin/bash

# Send an initialize request
echo '{"jsonrpc": "2.0", "method": "initialize", "params": {}, "id": 1}'

# Send a tools/list request
echo '{"jsonrpc": "2.0", "method": "tools/list", "params": {}, "id": 2}'

# Send a tools/call request for add
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "add", "arguments": {"a": 5, "b": 3}}, "id": 3}'

# Send a tools/call request for multiply
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "multiply", "arguments": {"a": 4, "b": 7}}, "id": 4}'

# Send a tools/call request for greet
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "greet", "arguments": {"name": "SwiftMCP"}}, "id": 5}'

# Send a tools/call request for ping
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "ping", "arguments": {}}, "id": 6}' 