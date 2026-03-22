#!/bin/sh
# Installs the Claude Code statusline into ~/.claude/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
TARGET="$CLAUDE_DIR/statusline-command.sh"

# Copy the script
mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/statusline-command.sh" "$TARGET"
chmod +x "$TARGET"
echo "Installed: $TARGET"

# Merge statusLine into settings.json
STATUS_LINE_JSON="{\"statusLine\":{\"type\":\"command\",\"command\":\"sh $TARGET\"}}"

if [ -f "$SETTINGS" ]; then
  if command -v jq > /dev/null 2>&1; then
    tmp=$(mktemp)
    jq --argjson sl "$STATUS_LINE_JSON" '. + $sl' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  else
    echo "Warning: jq not found — could not merge settings.json automatically."
    echo "Add the following to $SETTINGS manually:"
    echo "  \"statusLine\": {\"type\": \"command\", \"command\": \"sh $TARGET\"}"
    exit 1
  fi
else
  printf '%s\n' "$STATUS_LINE_JSON" > "$SETTINGS"
fi

echo "Updated: $SETTINGS"
echo "Done. Restart Claude Code to apply."
