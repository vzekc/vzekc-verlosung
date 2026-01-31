#!/bin/bash
# Wrapper to run discourse-mcp-server with correct Ruby environment via mise

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Discourse path - can be overridden via env var, defaults to sibling directory
export DISCOURSE_PATH="${DISCOURSE_PATH:-$(dirname "$SCRIPT_DIR")/../discourse}"
DISCOURSE_PATH="$(cd "$DISCOURSE_PATH" && pwd)"  # Resolve to absolute path

# Change to discourse directory (mise reads .ruby-version from cwd)
cd "$DISCOURSE_PATH"

# Activate mise - try common locations
if command -v mise &> /dev/null; then
  eval "$(mise activate bash)"
elif [ -x "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate bash)"
else
  echo "Error: mise not found" >&2
  exit 1
fi

# Run our custom MCP server
exec ruby "$SCRIPT_DIR/discourse-mcp-server"
