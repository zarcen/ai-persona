#!/usr/bin/env bash
# scripts/validate.sh
# Validates all skills: checks required frontmatter fields,
# detects broken references, ensures cursor-rules/ is up to date,
# and verifies .claude-plugin/ manifests are in sync with skills/.
#
# Usage:
#   ./scripts/validate.sh               # validate all skills
#   ./scripts/validate.sh k8s-operator  # validate one skill

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

pass=0; fail=0

ok()   { echo "  ✓ $*"; pass=$((pass+1)); }
err()  { echo "  ✗ $*"; fail=$((fail+1)); }
log()  { echo "▶ $*"; }

validate_skill() {
  local skill_dir="$1"
  local name
  name="$(basename "$skill_dir")"
  local skill_md="$skill_dir/SKILL.md"

  log "$name"

  # Required file
  if [[ ! -f "$skill_md" ]]; then
    err "Missing SKILL.md"
    return
  fi
  ok "SKILL.md exists"

  # Required frontmatter fields (handles single-line and folded/block YAML values)
  for field in name description; do
    local val
    val="$(awk "
      /^---/{ if(p)exit; p=1; next }
      p && /^${field}:/{
        sub(/^${field}:[[:space:]]*/,\"\"); sub(/^[>|][[:space:]]*/,\"\")
        if(length(\$0)>0){ print; exit }
        # folded/block: grab first non-empty continuation line
        while((getline line)>0){
          if(line~/^[[:space:]]+/){ sub(/^[[:space:]]*/,\"\",line); print line; exit }
          else exit
        }
      }
    " "$skill_md" | tr -d '"')"
    if [[ -z "$val" ]]; then
      err "Missing frontmatter field: $field"
    else
      ok "frontmatter.$field = ${val:0:60}..."
    fi
  done

  # Check references exist if directory is present
  local refs_dir="$skill_dir/references"
  if [[ -d "$refs_dir" ]]; then
    for ref in "$refs_dir"/*.md; do
      [[ -f "$ref" ]] && ok "reference exists: $(basename "$ref")" || true
    done

    # Check cross-references in SKILL.md (lines like `references/foo.md`)
    while IFS= read -r linked; do
      local linked_path="$skill_dir/$linked"
      if [[ ! -f "$linked_path" ]]; then
        err "Broken reference link: $linked"
      else
        ok "reference link OK: $linked"
      fi
    done < <(grep -oE 'references/[a-z0-9_-]+\.md' "$skill_md" | sort -u || true)
  fi

  # Check cursor-rules output is present and non-empty
  local mdc="$REPO_ROOT/cursor-rules/${name}.mdc"
  if [[ ! -f "$mdc" ]]; then
    err "cursor-rules/${name}.mdc missing — run ./scripts/build.sh $name"
  elif [[ ! -s "$mdc" ]]; then
    err "cursor-rules/${name}.mdc is empty"
  else
    ok "cursor-rules/${name}.mdc exists ($(wc -l < "$mdc") lines)"
  fi

  # Check per-skill .claude-plugin/plugin.json exists
  local plugin_json="$skill_dir/.claude-plugin/plugin.json"
  if [[ ! -f "$plugin_json" ]]; then
    err ".claude-plugin/plugin.json missing — run ./scripts/build.sh $name"
  elif ! python3 -c "import json,sys; json.load(sys.stdin)" < "$plugin_json" 2>/dev/null; then
    err ".claude-plugin/plugin.json is invalid JSON"
  else
    ok ".claude-plugin/plugin.json exists"
  fi
}

validate_marketplace() {
  log "marketplace.json"

  if [[ ! -f "$MARKETPLACE_JSON" ]]; then
    err "marketplace.json missing — run ./scripts/build.sh"
    return
  fi

  if ! python3 -c "import json,sys; json.load(sys.stdin)" < "$MARKETPLACE_JSON" 2>/dev/null; then
    err "marketplace.json is invalid JSON"
    return
  fi
  ok "marketplace.json is valid JSON"

  # Every skill directory must have a matching plugin entry
  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name="$(basename "$skill_dir")"
    [[ -f "$skill_dir/SKILL.md" ]] || continue

    if grep -q "\"name\": \"${name}\"" "$MARKETPLACE_JSON"; then
      ok "marketplace.json has entry for $name"
    else
      err "marketplace.json missing entry for skill: $name"
    fi
  done

  # Every plugin entry in marketplace.json must have a matching skill directory
  local plugin_names
  plugin_names="$(python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    print(p['name'])
" < "$MARKETPLACE_JSON")"

  while IFS= read -r pname; do
    [[ -z "$pname" ]] && continue
    if [[ -d "$SKILLS_DIR/$pname" && -f "$SKILLS_DIR/$pname/SKILL.md" ]]; then
      ok "plugin '$pname' maps to skills/$pname/"
    else
      err "plugin '$pname' in marketplace.json has no matching skills/$pname/SKILL.md"
    fi
  done <<< "$plugin_names"
}

# ── main ───────────────────────────────────────────────────────────────────────

if [[ $# -eq 1 ]]; then
  validate_skill "$SKILLS_DIR/$1"
else
  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] && validate_skill "$skill_dir"
  done
fi

validate_marketplace

echo ""
echo "Result: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
