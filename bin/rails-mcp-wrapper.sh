#!/bin/bash
# Wrapper to run rails-mcp-server with correct Ruby environment via mise

cd /Users/hans/Development/vzekc/discourse

# Use mise exec to run with the correct Ruby environment
# This ensures child processes (bin/rails) also use the correct Ruby
exec /Users/hans/.local/bin/mise exec -- rails-mcp-server "$@"
