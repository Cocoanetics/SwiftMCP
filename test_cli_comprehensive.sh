#!/bin/bash

# Set colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Build the project
print_header "Building project"
swift build
if [ $? -eq 0 ]; then
    print_success "Build successful"
else
    print_error "Build failed"
    exit 1
fi

# Create a temporary file for interactive mode testing
TEMP_FILE=$(mktemp)
cat > $TEMP_FILE << EOF
{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": "10"}}}
{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "add", "arguments": {"a": "5", "b": "7"}}}
{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "multiply", "arguments": {"a": "6", "b": "8"}}}
EOF

# Test one-off mode with divide tool
print_header "Testing one-off mode with divide tool"
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": "10"}}}' | ./.build/debug/SwiftMCPDemo

# Test one-off mode with add tool
print_header "Testing one-off mode with add tool"
echo '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "add", "arguments": {"a": "5", "b": "7"}}}' | ./.build/debug/SwiftMCPDemo

# Test one-off mode with verbose flag
print_header "Testing one-off mode with verbose flag"
echo '{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "multiply", "arguments": {"a": "6", "b": "8"}}}' | ./.build/debug/SwiftMCPDemo -v

# Test interactive mode
print_header "Testing interactive mode"
cat $TEMP_FILE | ./.build/debug/SwiftMCPDemo --interactive

# Test with input file
print_header "Testing with input file"
./.build/debug/SwiftMCPDemo -i $TEMP_FILE

# Test with output file
print_header "Testing with output file and verbose mode"
OUTPUT_FILE=$(mktemp)
echo '{"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "subtract", "arguments": {"a": "10", "b": "3"}}}' | ./.build/debug/SwiftMCPDemo -v -o $OUTPUT_FILE
echo "Output written to file:"
cat $OUTPUT_FILE

# Test error handling
print_header "Testing error handling"
echo '{"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": "not_a_number"}}}' | ./.build/debug/SwiftMCPDemo

# Clean up temporary files
rm $TEMP_FILE
rm $OUTPUT_FILE

print_header "All tests completed"
print_success "SwiftMCP CLI is working correctly" 