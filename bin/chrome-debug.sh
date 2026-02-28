#!/bin/bash
# Launch Chrome with remote debugging for use with Puppeteer MCP server.
# Uses a dedicated user-data-dir so it runs independently from your regular Chrome.
# Log into your dev server once - the session persists across restarts.

PORT="${1:-9222}"
USER_DATA_DIR="$HOME/.chrome-dev-debug"

/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$USER_DATA_DIR" \
  http://127.0.0.1:4200/ 2>/dev/null &

echo "Chrome launched with remote debugging on port $PORT"
echo "User data dir: $USER_DATA_DIR"
echo "Log into your dev server if this is the first run."
