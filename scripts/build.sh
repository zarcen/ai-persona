#!/usr/bin/env bash
# scripts/build.sh
# Builds agent-specific artifacts from skill sources in skills/.
#
# Usage:
#   ./scripts/build.sh               # build all skills
#   ./scripts/build.sh k8s-operator  # build one skill
#
# Source:
#   skills/<name>/SKILL.md + references/       (author here)
#
# Output (all derived / committed):
#   cursor-rules/<name>.mdc                    (Cursor rule file)
#   plugins/<name>/                            (Claude Code plugin — symlinks into skills/)
#   .claude-plugin/marketplace.json            (Claude Code marketplace catalog)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
PLUGINS_DIR="$REPO_ROOT/plugins"
CURSOR_RULES_DIR="$REPO_ROOT/cursor-rules"
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

# Build a single skill into agent-specific artifacts:
#   cursor-rules/<name>.mdc           (Cursor)
#   plugins/<name>/                   (Claude Code — plugin.json + symlink)
build_skill() {
  local skill_dir="$1"
  local name
  name="$(basename "$skill_dir")"
  local skill_md="$skill_dir/SKILL.md"
  local refs_dir="$skill_dir/references"
  local mdc_file="$CURSOR_RULES_DIR/${name}.mdc"

  log "Building $name ..."

  [[ -f "$skill_md" ]] || err "Missing SKILL.md in $skill_dir"

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
  } > "$mdc_file"

  ok "$name → cursor-rules/${name}.mdc"

  # ── write plugins/<name>/ (Claude Code plugin) ────────────────────────────
  local plugin_root="$PLUGINS_DIR/$name"
  local plugin_meta="$plugin_root/.claude-plugin"
  local plugin_skills="$plugin_root/skills"

  mkdir -p "$plugin_meta" "$plugin_skills"

  local desc_escaped
  desc_escaped="$(json_escape "$description")"

  cat > "$plugin_meta/plugin.json" <<EOF
{
  "name": "${name}",
  "description": "${desc_escaped}",
  "author": {
    "name": "zarcen"
  },
  "homepage": "https://github.com/zarcen/ai-persona/tree/main/skills/${name}"
}
EOF

  # Symlink: plugins/<name>/skills/<name> → ../../../skills/<name>
  local link_target="$plugin_skills/$name"
  rm -f "$link_target"
  ln -s "../../../skills/$name" "$link_target"

  ok "$name → plugins/${name}/ (plugin.json + skills/ symlink)"
}

# Regenerate .claude-plugin/marketplace.json from all skill directories.
# Merges into the existing file so manually-added fields are preserved.
build_marketplace() {
  log "Generating marketplace.json ..."

  mkdir -p "$(dirname "$MARKETPLACE_JSON")"

  # Collect skill names and descriptions into a temp file (tab-separated)
  local tmpfile
  tmpfile="$(mktemp)"

  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name="$(basename "$skill_dir")"
    local skill_md="$skill_dir/SKILL.md"
    [[ -f "$skill_md" ]] || continue

    local description
    description="$(extract_field description "$skill_md")"
    printf '%s\t%s\n' "$name" "$description" >> "$tmpfile"
  done

  local count
  count="$(python3 - "$MARKETPLACE_JSON" "$tmpfile" <<'PYEOF'
import json, sys, os

marketplace_path = sys.argv[1]
data_file = sys.argv[2]

generated = {}
with open(data_file) as f:
    for line in f:
        line = line.rstrip("\n")
        if "\t" not in line:
            continue
        name, desc = line.split("\t", 1)
        generated[name] = desc

if os.path.exists(marketplace_path):
    with open(marketplace_path) as f:
        marketplace = json.load(f)
else:
    marketplace = {
        "name": "ai-persona",
        "owner": {"name": "zarcen"},
        "metadata": {"description": "Reusable agent skills for AI coding agents"},
        "plugins": []
    }

marketplace = {k: v for k, v in marketplace.items() if k != "//"}

existing_by_name = {}
for plugin in marketplace.get("plugins", []):
    existing_by_name[plugin["name"]] = plugin

new_plugins = []
for name in sorted(generated):
    if name in existing_by_name:
        entry = existing_by_name[name]
        entry["description"] = generated[name]
        entry["source"] = "./plugins/" + name
        new_plugins.append(entry)
    else:
        new_plugins.append({
            "name": name,
            "source": "./plugins/" + name,
            "description": generated[name],
            "version": "1.0.0"
        })

marketplace["plugins"] = new_plugins

with open(marketplace_path, "w") as f:
    json.dump(marketplace, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(len(new_plugins))
PYEOF
)"

  rm -f "$tmpfile"
  ok "marketplace.json (${count} plugin(s))"
}

# ── main ───────────────────────────────────────────────────────────────────────

mkdir -p "$CURSOR_RULES_DIR" "$PLUGINS_DIR"

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
