#!/usr/bin/env bash
# scripts/validate.sh
# Validates all skills: checks required frontmatter fields,
# detects broken references, and ensures dist/ is up to date.
#
# Usage:
#   ./scripts/validate.sh               # validate all skills
#   ./scripts/validate.sh k8s-operator  # validate one skill

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

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

  # Check dist is present and non-empty
  local mdc="$skill_dir/dist/${name}.mdc"
  if [[ ! -f "$mdc" ]]; then
    err "dist/${name}.mdc missing — run ./scripts/build.sh $name"
  elif [[ ! -s "$mdc" ]]; then
    err "dist/${name}.mdc is empty"
  else
    ok "dist/${name}.mdc exists ($(wc -l < "$mdc") lines)"
  fi

  # Check flat dist mirror
  local flat="$REPO_ROOT/dist/${name}.mdc"
  if [[ ! -f "$flat" ]]; then
    err "dist/${name}.mdc missing from repo root dist/ — run ./scripts/build.sh"
  else
    ok "root dist/${name}.mdc present"
  fi
}

if [[ $# -eq 1 ]]; then
  validate_skill "$SKILLS_DIR/$1"
else
  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] && validate_skill "$skill_dir"
  done
fi

echo ""
echo "Result: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
