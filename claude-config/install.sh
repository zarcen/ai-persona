#!/bin/sh
# Symlinks claude-config files into ~/.claude/
# Run from anywhere — detects repo root from this script's location.
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/claude-config"
CLAUDE_DIR="$HOME/.claude"

mkdir -p "$CLAUDE_DIR"

link() {
  src="$1"
  dst="$2"
  if [ -L "$dst" ]; then
    # Already a symlink — update it
    ln -sf "$src" "$dst"
    echo "updated symlink: $dst -> $src"
  elif [ -e "$dst" ]; then
    # Real file exists — back it up
    bak="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    echo "backed up existing file: $bak"
    ln -s "$src" "$dst"
    echo "created symlink: $dst -> $src"
  else
    ln -s "$src" "$dst"
    echo "created symlink: $dst -> $src"
  fi
}

# settings.json — all shared Claude Code settings live here.
# Machine-specific overrides go in ~/.claude/settings.local.json (untracked).
link "$CONFIG_DIR/settings.json" "$CLAUDE_DIR/settings.json"

# Supporting scripts referenced by settings.json
link "$CONFIG_DIR/statusline/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"

echo ""
echo "Done. Restart Claude Code to apply."
echo "For machine-specific overrides, edit: $CLAUDE_DIR/settings.local.json"
