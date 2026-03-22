#!/usr/bin/env bash
# cluster-name.sh — print a deterministic kind cluster name for the current repo.
#
# Output: kind-<repo-slug>-<git-hash>
# Example: kind-my-operator-a3f1c2
#
# Rules:
#   - repo slug: basename of git root, lowercased, non-alphanumeric → dash, trimmed to 20 chars
#   - hash: 6-char git short SHA; falls back to md5 of CWD when not in a git repo

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REPO_NAME=$(basename "$REPO_ROOT")

# Sanitize: lowercase, replace runs of non-alphanumeric with a single dash, strip trailing dash
REPO_SLUG=$(
  echo "$REPO_NAME" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '-' \
    | cut -c1-20 \
    | sed 's/-$//'
)

# 6-char hash
GIT_HASH=$(git rev-parse --short=6 HEAD 2>/dev/null \
  || echo "$REPO_ROOT" | md5sum | cut -c1-6)

echo "kind-${REPO_SLUG}-${GIT_HASH}"
