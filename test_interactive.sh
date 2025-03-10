#!/bin/bash

# Test the simplified SwiftMCPDemo
# This script sends multiple JSON-RPC requests to the SwiftMCPDemo command

# Build the project
swift build

# Run the command with input
(
  # Send a ping request
  echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "ping", "arguments": {}}}'
  
  # Send an add request
  echo '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "add", "arguments": {"a": 5, "b": 3}}}'
  
  # Send a greet request
  echo '{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "greet", "arguments": {"name": "World"}}}'
  
  # Wait a bit to ensure all responses are received
  sleep 1
  
  # Send SIGINT to terminate the process
  kill -INT $$
) | swift run SwiftMCPDemo 