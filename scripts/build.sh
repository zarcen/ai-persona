#!/usr/bin/env bash
# scripts/build.sh
# Generates root marketplace catalog files from authored plugin manifests.
#
# Usage:
#   ./scripts/build.sh               # build all plugins
#   ./scripts/build.sh k8s           # build one plugin
#
# Source (author these — never generated):
#   plugins/<name>/.claude-plugin/plugin.json
#   plugins/<name>/.cursor-plugin/plugin.json
#   plugins/<name>/skills/<skill>/SKILL.md + references/
#
# Output (generated / committed):
#   .claude-plugin/marketplace.json            (Claude Code marketplace catalog)
#   .cursor-plugin/marketplace.json            (Cursor marketplace catalog)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_DIR="$REPO_ROOT/plugins"
CLAUDE_MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CURSOR_MARKETPLACE_JSON="$REPO_ROOT/.cursor-plugin/marketplace.json"

# ── helpers ────────────────────────────────────────────────────────────────────

log()  { echo "▶ $*"; }
ok()   { echo "✓ $*"; }
err()  { echo "✗ $*" >&2; exit 1; }

# Validate a single plugin directory has required authored files.
check_plugin() {
  local plugin_dir="$1"
  local name
  name="$(basename "$plugin_dir")"

  [[ -f "$plugin_dir/.claude-plugin/plugin.json" ]] \
    || err "$name: missing .claude-plugin/plugin.json — author this file"
  [[ -f "$plugin_dir/.cursor-plugin/plugin.json" ]] \
    || err "$name: missing .cursor-plugin/plugin.json — author this file"

  # Ensure assets/logo.svg symlink exists
  local logo="$plugin_dir/assets/logo.svg"
  if [[ ! -L "$logo" ]]; then
    mkdir -p "$plugin_dir/assets"
    rm -f "$logo"
    ln -s "../../../logo.svg" "$logo"
    ok "$name → created assets/logo.svg symlink"
  fi
}

# Regenerate root marketplace JSON files from all authored plugin manifests.
build_marketplace() {
  log "Generating marketplace.json files ..."

  mkdir -p "$(dirname "$CLAUDE_MARKETPLACE_JSON")" "$(dirname "$CURSOR_MARKETPLACE_JSON")"

  python3 - "$PLUGINS_DIR" "$CLAUDE_MARKETPLACE_JSON" "$CURSOR_MARKETPLACE_JSON" <<'PYEOF'
import json, sys, os

plugins_dir       = sys.argv[1]
claude_path       = sys.argv[2]
cursor_path       = sys.argv[3]

def load_or_default(path, default):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return default

# Collect plugin entries by reading authored plugin.json files
claude_entries = []
cursor_entries = []

for name in sorted(os.listdir(plugins_dir)):
    plugin_dir = os.path.join(plugins_dir, name)
    if not os.path.isdir(plugin_dir):
        continue

    claude_json = os.path.join(plugin_dir, ".claude-plugin", "plugin.json")
    cursor_json = os.path.join(plugin_dir, ".cursor-plugin", "plugin.json")

    if not os.path.exists(claude_json) or not os.path.exists(cursor_json):
        continue

    with open(claude_json) as f:
        cp = json.load(f)
    with open(cursor_json) as f:
        crp = json.load(f)

    if "version" not in cp:
        print(f"ERROR: {name}/.claude-plugin/plugin.json missing 'version' field", file=sys.stderr)
        sys.exit(1)
    claude_entries.append({
        "name": cp["name"],
        "source": f"./plugins/{name}",
        "description": cp.get("description", ""),
        "version": cp["version"]
    })
    cursor_entries.append({
        "name": crp["name"],
        "source": f"./plugins/{name}",
        "description": crp.get("description", ""),
        "version": crp.get("version", "")
    })

# ── Claude Code marketplace ───────────────────────────────────────────────
claude = load_or_default(claude_path, {
    "name": "ai-persona",
    "owner": {"name": "zarcen"},
    "metadata": {"description": "Reusable agent skills for AI coding agents"},
    "plugins": []
})
claude = {k: v for k, v in claude.items() if k != "//"}
claude["plugins"] = claude_entries
with open(claude_path, "w") as f:
    json.dump(claude, f, indent=2, ensure_ascii=False)
    f.write("\n")

# ── Cursor marketplace ────────────────────────────────────────────────────
cursor = load_or_default(cursor_path, {
    "name": "ai-persona",
    "owner": {"name": "zarcen"},
    "metadata": {
        "description": "Reusable agent skills for AI coding agents",
        "version": "1.0.0",
        "pluginRoot": "plugins"
    },
    "plugins": []
})
cursor = {k: v for k, v in cursor.items() if k != "//"}
cursor["plugins"] = cursor_entries
# Remove empty email field if present
if isinstance(cursor.get("owner"), dict):
    cursor["owner"].pop("email", None)
    if not cursor["owner"].get("email"):
        cursor["owner"] = {k: v for k, v in cursor["owner"].items() if v}
with open(cursor_path, "w") as f:
    json.dump(cursor, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"{len(claude_entries)} plugin(s)")
PYEOF
}

# ── main ───────────────────────────────────────────────────────────────────────

if [[ $# -eq 1 ]]; then
  plugin_dir="$PLUGINS_DIR/$1"
  [[ -d "$plugin_dir" ]] || err "Plugin '$1' not found in $PLUGINS_DIR"
  log "Checking $1 ..."
  check_plugin "$plugin_dir"
  ok "$1 looks good"
  build_marketplace
else
  found=0
  for plugin_dir in "$PLUGINS_DIR"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    log "Checking $(basename "$plugin_dir") ..."
    check_plugin "$plugin_dir"
    ok "$(basename "$plugin_dir") looks good"
    found=$((found + 1))
  done
  [[ $found -gt 0 ]] || err "No plugin directories found in $PLUGINS_DIR"
  build_marketplace
  log "Built $found plugin(s)."
fi
