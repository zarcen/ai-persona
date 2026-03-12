#!/usr/bin/env bash
# scripts/build.sh
# Builds .mdc files for all skills (or a single skill if passed as argument).
#
# Usage:
#   ./scripts/build.sh               # build all skills
#   ./scripts/build.sh k8s-operator  # build one skill
#
# Output:
#   skills/<name>/dist/<name>.mdc    (per-skill artifact)
#   dist/<name>.mdc                  (flat mirror for curl installs)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
DIST_DIR="$REPO_ROOT/dist"

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

# Build a single skill directory into a .mdc file
build_skill() {
  local skill_dir="$1"
  local name
  name="$(basename "$skill_dir")"
  local skill_md="$skill_dir/SKILL.md"
  local refs_dir="$skill_dir/references"
  local out_dir="$skill_dir/dist"
  local out_file="$out_dir/${name}.mdc"

  log "Building $name ..."

  [[ -f "$skill_md" ]] || err "Missing SKILL.md in $skill_dir"

  # Extract description and name from SKILL.md frontmatter
  local description
  description="$(extract_field description "$skill_md")"
  [[ -n "$description" ]] || err "$name: could not extract 'description' from SKILL.md frontmatter"

  mkdir -p "$out_dir"

  # ── write .mdc ──────────────────────────────────────────────────────────────
  {
    # Cursor frontmatter
    printf -- "---\n"
    printf "description: %s\n" "$description"
    printf "globs:\n"

    # Auto-generate globs from SKILL.md frontmatter if present, else use defaults
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

    # Inline SKILL.md body (strip its own frontmatter)
    awk '/^---/{if(p)exit; p=1; next} p' "$skill_md"

    # Inline each reference file
    if [[ -d "$refs_dir" ]]; then
      for ref in "$refs_dir"/*.md; do
        [[ -f "$ref" ]] || continue
        printf "\n\n---\n\n"
        cat "$ref"
      done
    fi
  } > "$out_file"

  # Copy to flat dist/ mirror
  cp "$out_file" "$DIST_DIR/${name}.mdc"

  ok "$name → skills/${name}/dist/${name}.mdc + dist/${name}.mdc"
}

# ── main ───────────────────────────────────────────────────────────────────────

mkdir -p "$DIST_DIR"

if [[ $# -eq 1 ]]; then
  # Build a single named skill
  skill_dir="$SKILLS_DIR/$1"
  [[ -d "$skill_dir" ]] || err "Skill '$1' not found in $SKILLS_DIR"
  build_skill "$skill_dir"
else
  # Build all skills
  found=0
  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    build_skill "$skill_dir"
    found=$((found + 1))
  done
  [[ $found -gt 0 ]] || err "No skill directories found in $SKILLS_DIR"
  log "Built $found skill(s)."
fi
