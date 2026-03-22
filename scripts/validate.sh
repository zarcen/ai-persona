#!/usr/bin/env bash
# scripts/validate.sh
# Validates all plugins: checks authored manifests, skill structure,
# reference links, and root marketplace catalogs.
#
# Usage:
#   ./scripts/validate.sh               # validate all plugins
#   ./scripts/validate.sh k8s           # validate one plugin

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_DIR="$REPO_ROOT/plugins"
CLAUDE_MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CURSOR_MARKETPLACE_JSON="$REPO_ROOT/.cursor-plugin/marketplace.json"

pass=0; fail=0

ok()   { echo "  ✓ $*"; pass=$((pass+1)); }
err()  { echo "  ✗ $*"; fail=$((fail+1)); }
log()  { echo "▶ $*"; }

validate_json_file() {
  local path="$1" label="$2"
  if [[ ! -f "$path" ]]; then
    err "$label missing"
    return 1
  fi
  if ! python3 -c "import json,sys; json.load(sys.stdin)" < "$path" 2>/dev/null; then
    err "$label is invalid JSON"
    return 1
  fi
  ok "$label is valid JSON"
  return 0
}

validate_plugin() {
  local plugin_dir="$1"
  local name
  name="$(basename "$plugin_dir")"

  log "$name"

  # Authored manifests
  validate_json_file "$plugin_dir/.claude-plugin/plugin.json" ".claude-plugin/plugin.json" || true

  local cursor_json="$plugin_dir/.cursor-plugin/plugin.json"
  if validate_json_file "$cursor_json" ".cursor-plugin/plugin.json"; then
    # Cursor plugin.json required fields
    for field in name displayName description; do
      local val
      val="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$field',''))" < "$cursor_json")"
      if [[ -z "$val" ]]; then
        err ".cursor-plugin/plugin.json missing required field: $field"
      else
        ok ".cursor-plugin/plugin.json.$field = ${val:0:60}"
      fi
    done
  fi

  # Version consistency — both plugin.json files must declare the same version
  local claude_json="$plugin_dir/.claude-plugin/plugin.json"
  if [[ -f "$claude_json" && -f "$cursor_json" ]]; then
    local claude_ver cursor_ver
    claude_ver="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version',''))" < "$claude_json")"
    cursor_ver="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version',''))" < "$cursor_json")"
    if [[ -z "$claude_ver" ]]; then
      err ".claude-plugin/plugin.json missing required field: version"
    elif [[ -z "$cursor_ver" ]]; then
      err ".cursor-plugin/plugin.json missing required field: version"
    elif [[ "$claude_ver" != "$cursor_ver" ]]; then
      err "version mismatch: .claude-plugin/plugin.json=$claude_ver vs .cursor-plugin/plugin.json=$cursor_ver"
    else
      ok "version consistent: $claude_ver"
    fi
  fi

  # Logo symlink
  local logo="$plugin_dir/assets/logo.svg"
  if [[ ! -L "$logo" ]]; then
    err "assets/logo.svg symlink missing — run ./scripts/build.sh $name"
  elif [[ ! -f "$logo" ]]; then
    err "assets/logo.svg symlink is broken"
  else
    ok "assets/logo.svg symlink OK"
  fi

  # Skills — at least one required
  local skill_count=0
  for skill_dir in "$plugin_dir/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"
    local skill_md="$skill_dir/SKILL.md"

    if [[ ! -f "$skill_md" ]]; then
      err "skills/$skill_name/SKILL.md missing"
      continue
    fi
    ok "skills/$skill_name/SKILL.md exists"
    skill_count=$((skill_count + 1))

    # Required frontmatter fields
    for field in name description; do
      local val
      val="$(awk "
        /^---/{ if(p)exit; p=1; next }
        p && /^${field}:/{
          sub(/^${field}:[[:space:]]*/,\"\"); sub(/^[>|][[:space:]]*/,\"\")
          if(length(\$0)>0){ print; exit }
          while((getline line)>0){
            if(line~/^[[:space:]]+/){ sub(/^[[:space:]]*/,\"\",line); print line; exit }
            else exit
          }
        }
      " "$skill_md" | tr -d '"')"
      if [[ -z "$val" ]]; then
        err "skills/$skill_name/SKILL.md missing frontmatter field: $field"
      else
        ok "skills/$skill_name/SKILL.md frontmatter.$field = ${val:0:60}"
      fi
    done

    # Reference links
    local refs_dir="$skill_dir/references"
    if [[ -d "$refs_dir" ]]; then
      while IFS= read -r linked; do
        local linked_path="$skill_dir/$linked"
        if [[ ! -f "$linked_path" ]]; then
          err "skills/$skill_name: broken reference link: $linked"
        else
          ok "skills/$skill_name: reference link OK: $linked"
        fi
      done < <(grep -oE 'references/[a-z0-9_-]+\.md' "$skill_md" | sort -u || true)
    fi
  done

  if [[ $skill_count -eq 0 ]]; then
    err "no skills found under skills/ — add at least one skill with a SKILL.md"
  fi
}

validate_marketplace_file() {
  local label="$1"
  local marketplace_json="$2"

  log "$label"

  if [[ ! -f "$marketplace_json" ]]; then
    err "$label missing — run ./scripts/build.sh"
    return
  fi

  if ! python3 -c "import json,sys; json.load(sys.stdin)" < "$marketplace_json" 2>/dev/null; then
    err "$label is invalid JSON"
    return
  fi
  ok "$label is valid JSON"

  # Every plugin directory must have a matching entry
  for plugin_dir in "$PLUGINS_DIR"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    local name
    name="$(basename "$plugin_dir")"

    if grep -q "\"name\": \"${name}\"" "$marketplace_json"; then
      ok "$label has entry for $name"
    else
      err "$label missing entry for plugin: $name"
    fi
  done

  # Every entry source must point into plugins/
  local plugin_sources
  plugin_sources="$(python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    src = p.get('source', '')
    if isinstance(src, str):
        print(p['name'] + '\t' + src)
" < "$marketplace_json")"

  while IFS=$'\t' read -r pname psource; do
    [[ -z "$pname" ]] && continue
    if [[ "$psource" == "./plugins/"* ]]; then
      ok "plugin '$pname' source → $psource"
    else
      err "plugin '$pname' source should be ./plugins/$pname but is $psource"
    fi
  done <<< "$plugin_sources"
}

# ── main ───────────────────────────────────────────────────────────────────────

if [[ $# -eq 1 ]]; then
  validate_plugin "$PLUGINS_DIR/$1"
else
  for plugin_dir in "$PLUGINS_DIR"/*/; do
    [[ -d "$plugin_dir" ]] && validate_plugin "$plugin_dir"
  done
fi

validate_marketplace_file ".claude-plugin/marketplace.json" "$CLAUDE_MARKETPLACE_JSON"
validate_marketplace_file ".cursor-plugin/marketplace.json" "$CURSOR_MARKETPLACE_JSON"

echo ""
echo "Result: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
