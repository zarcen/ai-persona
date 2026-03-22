#!/usr/bin/env bash
# check-kustomization.sh — compare kustomization.yaml resources against YAML files on disk.
#
# Usage:
#   ./scripts/check-kustomization.sh [SAMPLES_DIR]
#
# Prints files present on disk but absent from kustomization.yaml.
# Exit code:
#   0  kustomization.yaml covers all YAML files (or does not exist)
#   1  one or more YAML files are missing from kustomization.yaml

set -uo pipefail

SAMPLES_DIR="${1:-config/samples}"
KUSTOMIZATION="${SAMPLES_DIR}/kustomization.yaml"

if [[ ! -f "${KUSTOMIZATION}" ]]; then
  echo "No kustomization.yaml found in ${SAMPLES_DIR} — skipping coverage check."
  exit 0
fi

mapfile -t ALL_YAML < <(
  find "${SAMPLES_DIR}" -maxdepth 1 -name "*.yaml" \
    -not -name "kustomization.yaml" \
    -not -name "_*" \
  | sort
)

MISSING=()
for F in "${ALL_YAML[@]}"; do
  BASENAME=$(basename "${F}")
  if ! grep -qE "^\s*-\s+${BASENAME}\s*$" "${KUSTOMIZATION}"; then
    MISSING+=("${F}")
  fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "OK: kustomization.yaml covers all ${#ALL_YAML[@]} YAML file(s) in ${SAMPLES_DIR}."
  exit 0
fi

echo "WARNING: ${#MISSING[@]} file(s) in ${SAMPLES_DIR} are NOT listed in kustomization.yaml:"
for F in "${MISSING[@]}"; do
  echo "  - $F"
done
echo ""
echo "To add them, append to ${KUSTOMIZATION}:"
for F in "${MISSING[@]}"; do
  echo "  - $(basename "$F")"
done
exit 1
