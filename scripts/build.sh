#!/usr/bin/env bash
# scripts/build.sh
# Builds .mdc files for all skills (or a single skill if passed as argument).
# Also generates Claude Code plugin manifests (.claude-plugin/) from SKILL.md frontmatter.
#
# Usage:
#   ./scripts/build.sh               # build all skills
#   ./scripts/build.sh k8s-operator  # build one skill
#
# Output:
#   cursor-rules/<name>.mdc                       (Cursor rule file)
#   skills/<name>/.claude-plugin/plugin.json       (Claude Code plugin manifest)
#   .claude-plugin/marketplace.json                (Claude Code marketplace catalog)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
DIST_DIR="$REPO_ROOT/cursor-rules"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

# ── helpers ────────────────────────────────────────────────────────────────────

log()  { echo "▶ $*"; }
ok()   { echo "✓ $*"; }
err()  { echo "✗ $*" >&2; exit 1; }

# Extract a YAML frontmatter field from SKILL.md (handles folded/block scalars)
# Joins continuation lines with spaces for folded (>) or newlines for literal (|).
# Usage: extract_field <field> <file>
extract_field() {
  local field="$1" file="$2"
  awk "
    /^---/{ if(p) exit; p=1; next }
    p && /^${field}:/{
      sub(/^${field}:[[:space:]]*/,\"\")
      folded = sub(/^>[[:space:]]*/,\"\")
      if(length(\$0)>0){ print; exit }
      result = \"\"
      while((getline line)>0){
        if(line ~ /^[[:space:]]+/){
          sub(/^[[:space:]]*/,\"\",line)
          if(result != \"\") result = result \" \"
          result = result line
        } else break
      }
      print result
      exit
    }
  " "$file" | tr -d '\"'
}

# Escape a string for safe JSON embedding
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

# Build a single skill directory into a .mdc file + .claude-plugin/plugin.json
build_skill() {
  local skill_dir="$1"
  local name
  name="$(basename "$skill_dir")"
  local skill_md="$skill_dir/SKILL.md"
  local refs_dir="$skill_dir/references"
  local out_file="$DIST_DIR/${name}.mdc"

  log "Building $name ..."

  [[ -f "$skill_md" ]] || err "Missing SKILL.md in $skill_dir"

  # Extract description from SKILL.md frontmatter
  local description
  description="$(extract_field description "$skill_md")"
  [[ -n "$description" ]] || err "$name: could not extract 'description' from SKILL.md frontmatter"

  # ── write .mdc (Cursor rule) ───────────────────────────────────────────────
  {
    printf -- "---\n"
    printf "description: %s\n" "$description"
    printf "globs:\n"

    local globs_raw
    globs_raw="$(awk '/^---/{if(p)exit; p=1; next} p && /^globs:/,/^[^ ]/' "$skill_md" \
      | grep '^\s*-' || true)"

    if [[ -n "$globs_raw" ]]; then
      echo "$globs_raw"
    else
      printf '  - "**/*.go"\n'
      printf '  - "**/*.yaml"\n'
    fi

    printf "alwaysApply: false\n"
    printf -- "---\n\n"

    awk '/^---/{if(p)exit; p=1; next} p' "$skill_md"

    if [[ -d "$refs_dir" ]]; then
      for ref in "$refs_dir"/*.md; do
        [[ -f "$ref" ]] || continue
        printf "\n\n---\n\n"
        cat "$ref"
      done
    fi
  } > "$out_file"

  ok "$name → cursor-rules/${name}.mdc"

  # ── write .claude-plugin/plugin.json (Claude Code plugin manifest) ─────────
  local plugin_dir="$skill_dir/.claude-plugin"
  mkdir -p "$plugin_dir"

  local desc_escaped
  desc_escaped="$(json_escape "$description")"

  cat > "$plugin_dir/plugin.json" <<EOF
{
  "name": "${name}",
  "description": "${desc_escaped}",
  "version": "1.0.0",
  "author": {
    "name": "zarcen"
  },
  "homepage": "https://github.com/zarcen/ai-persona/tree/main/skills/${name}"
}
EOF

  ok "$name → skills/${name}/.claude-plugin/plugin.json"
}

# Regenerate .claude-plugin/marketplace.json from all skill directories
build_marketplace() {
  log "Generating marketplace.json ..."

  mkdir -p "$(dirname "$MARKETPLACE_JSON")"

  local plugins_json=""
  local first=true

  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name="$(basename "$skill_dir")"
    local skill_md="$skill_dir/SKILL.md"
    [[ -f "$skill_md" ]] || continue

    local description
    description="$(extract_field description "$skill_md")"
    local desc_escaped
    desc_escaped="$(json_escape "$description")"

    if [[ "$first" == "true" ]]; then
      first=false
    else
      plugins_json="${plugins_json},"
    fi

    plugins_json="${plugins_json}
    {
      \"name\": \"${name}\",
      \"source\": \"${name}\",
      \"description\": \"${desc_escaped}\",
      \"version\": \"1.0.0\"
    }"
  done

  cat > "$MARKETPLACE_JSON" <<EOF
{
  "name": "ai-persona",
  "owner": {
    "name": "zarcen"
  },
  "metadata": {
    "description": "Reusable agent skills for AI coding agents",
    "pluginRoot": "./skills"
  },
  "plugins": [${plugins_json}
  ]
}
EOF

  local count
  count="$(python3 -c "import json,sys; print(len(json.load(sys.stdin).get('plugins',[])))" < "$MARKETPLACE_JSON")"
  ok "marketplace.json (${count} plugin(s))"
}

# ── main ───────────────────────────────────────────────────────────────────────

mkdir -p "$DIST_DIR"

if [[ $# -eq 1 ]]; then
  skill_dir="$SKILLS_DIR/$1"
  [[ -d "$skill_dir" ]] || err "Skill '$1' not found in $SKILLS_DIR"
  build_skill "$skill_dir"
  build_marketplace
else
  found=0
  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    build_skill "$skill_dir"
    found=$((found + 1))
  done
  [[ $found -gt 0 ]] || err "No skill directories found in $SKILLS_DIR"
  build_marketplace
  log "Built $found skill(s)."
fi
