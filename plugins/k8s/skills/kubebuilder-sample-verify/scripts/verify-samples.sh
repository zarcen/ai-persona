#!/usr/bin/env bash
# verify-samples.sh — validate kubebuilder CR samples against live CRD schemas.
#
# Usage:
#   ./scripts/verify-samples.sh CLUSTER_NAME [SAMPLES_DIR]
#
# Arguments:
#   CLUSTER_NAME  — kind cluster to target (e.g. kind-my-operator-a3f1c2)
#   SAMPLES_DIR   — directory containing CR YAML files (default: config/samples)
#
# Behaviour:
#   1. If kustomization.yaml exists in SAMPLES_DIR:
#      a. Compare its resources: list against all *.yaml files on disk.
#      b. If files are missing from kustomization.yaml, prompt the user:
#           [K] Use kustomization.yaml as-is
#           [A] Also validate missing files individually
#           [Q] Quit so the user can update kustomization.yaml first
#      c. Validate via `kubectl kustomize | kubectl apply --dry-run=server`.
#      d. If user chose [A], additionally validate missing files individually.
#   2. If kustomization.yaml does not exist, validate each *.yaml individually.
#
# Exit code:
#   0  all samples passed
#   1  one or more samples failed validation

set -uo pipefail

CLUSTER_NAME="${1:?Usage: verify-samples.sh CLUSTER_NAME [SAMPLES_DIR]}"
SAMPLES_DIR="${2:-config/samples}"
CONTEXT="kind-${CLUSTER_NAME}"
KUSTOMIZATION="${SAMPLES_DIR}/kustomization.yaml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_kustomize_drydrun() {
  kubectl kustomize "${SAMPLES_DIR}" \
    | kubectl apply -f - \
      --context "${CONTEXT}" \
      --dry-run=server \
      2>&1
}

run_individual_dryrun() {
  # $1 = file path; sets INDIV_OUTPUT and INDIV_EXIT
  INDIV_OUTPUT=$(kubectl apply -f "$1" \
    --context "${CONTEXT}" \
    --dry-run=server \
    2>&1)
  INDIV_EXIT=$?
}

print_report_header() {
  local crd_count
  crd_count=$(kubectl get crds --context "${CONTEXT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo ""
  echo "=== Kubebuilder Sample Verification Report ==="
  echo "Cluster:   ${CLUSTER_NAME}"
  echo "CRDs:      ${crd_count} installed"
  echo "Samples:   ${TOTAL} checked"
  echo ""
}

print_individual_results() {
  if [[ ${#PASS[@]} -gt 0 ]]; then
    echo "PASSED (${#PASS[@]}):"
    for S in "${PASS[@]}"; do echo "  ✓ $S"; done
  fi

  if [[ ${#FAIL[@]} -gt 0 ]]; then
    echo ""
    echo "FAILED (${#FAIL[@]}):"
    for S in "${FAIL[@]}"; do
      echo "  ✗ $S"
      echo "${ERROR_MAP[$S]}" | sed 's/^/      /'
    done
  fi
}

# ---------------------------------------------------------------------------
# Step 1 — Collect all YAML files (excluding kustomization.yaml and _ patches)
# ---------------------------------------------------------------------------

mapfile -t ALL_YAML < <(
  find "${SAMPLES_DIR}" -maxdepth 1 -name "*.yaml" \
    -not -name "kustomization.yaml" \
    -not -name "_*" \
  | sort
)

if [[ ${#ALL_YAML[@]} -eq 0 && ! -f "${KUSTOMIZATION}" ]]; then
  echo "No sample manifests found in ${SAMPLES_DIR}. Nothing to verify."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 2 — kustomization.yaml branch
# ---------------------------------------------------------------------------

USE_KUSTOMIZE=false
VALIDATE_MISSING=false
MISSING=()

if [[ -f "${KUSTOMIZATION}" ]]; then
  USE_KUSTOMIZE=true

  # Find YAML files on disk that are NOT referenced in kustomization.yaml
  for F in "${ALL_YAML[@]}"; do
    BASENAME=$(basename "${F}")
    if ! grep -qE "^\s*-\s+${BASENAME}\s*$" "${KUSTOMIZATION}"; then
      MISSING+=("${F}")
    fi
  done

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "WARNING: The following YAML files exist in ${SAMPLES_DIR}/ but are NOT listed"
    echo "in kustomization.yaml. They will be skipped if kustomization is used:"
    echo ""
    for F in "${MISSING[@]}"; do echo "  - $F"; done
    echo ""
    echo "Options:"
    echo "  [K] Use kustomization.yaml as-is (skip the missing files)"
    echo "  [A] Also validate the missing files individually (in addition to kustomization)"
    echo "  [Q] Quit — I'll update kustomization.yaml first"
    echo ""
    read -r -p "Choice [K/A/Q]: " CHOICE
    case "${CHOICE^^}" in
      K)
        VALIDATE_MISSING=false
        ;;
      A)
        VALIDATE_MISSING=true
        ;;
      Q)
        echo "Aborted. Please update ${KUSTOMIZATION} and re-run."
        exit 0
        ;;
      *)
        echo "Unknown choice '${CHOICE}'. Aborting."
        exit 1
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# Step 3 — Run validation
# ---------------------------------------------------------------------------

PASS=()
FAIL=()
declare -A ERROR_MAP
KUSTOMIZE_LABEL="kustomize:${SAMPLES_DIR}"

if [[ "${USE_KUSTOMIZE}" == true ]]; then
  echo "==> Validating via kustomize: ${KUSTOMIZATION}"
  KUSTOMIZE_OUTPUT=$(run_kustomize_drydrun)
  KUSTOMIZE_EXIT=$?

  if [[ ${KUSTOMIZE_EXIT} -eq 0 ]]; then
    PASS+=("${KUSTOMIZE_LABEL}")
  else
    FAIL+=("${KUSTOMIZE_LABEL}")
    ERROR_MAP["${KUSTOMIZE_LABEL}"]="${KUSTOMIZE_OUTPUT}"
  fi

  # Individual validation of missing files (user chose [A])
  if [[ "${VALIDATE_MISSING}" == true && ${#MISSING[@]} -gt 0 ]]; then
    echo "==> Also validating ${#MISSING[@]} missing file(s) individually"
    for SAMPLE in "${MISSING[@]}"; do
      run_individual_dryrun "${SAMPLE}"
      if [[ ${INDIV_EXIT} -eq 0 ]]; then
        PASS+=("${SAMPLE} (not in kustomization)")
      else
        FAIL+=("${SAMPLE} (not in kustomization)")
        ERROR_MAP["${SAMPLE} (not in kustomization)"]="${INDIV_OUTPUT}"
      fi
    done
  fi
else
  # No kustomization.yaml — validate every YAML individually
  echo "==> No kustomization.yaml found. Validating ${#ALL_YAML[@]} file(s) individually."
  for SAMPLE in "${ALL_YAML[@]}"; do
    run_individual_dryrun "${SAMPLE}"
    if [[ ${INDIV_EXIT} -eq 0 ]]; then
      PASS+=("${SAMPLE}")
    else
      FAIL+=("${SAMPLE}")
      ERROR_MAP["${SAMPLE}"]="${INDIV_OUTPUT}"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Step 4 — Report
# ---------------------------------------------------------------------------

TOTAL=$(( ${#PASS[@]} + ${#FAIL[@]} ))
print_report_header
print_individual_results

echo ""
echo "=== Summary ==="
echo "  Passed: ${#PASS[@]} / ${TOTAL}"
echo "  Failed: ${#FAIL[@]} / ${TOTAL}"
echo ""

if [[ ${#FAIL[@]} -gt 0 ]]; then
  exit 1
fi
exit 0
