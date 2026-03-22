#!/usr/bin/env bash
# create-cluster.sh — create an ephemeral kind cluster for sample verification.
#
# Usage:
#   ./scripts/create-cluster.sh [CLUSTER_NAME] [K8S_VERSION]
#
# Defaults:
#   CLUSTER_NAME  — output of scripts/cluster-name.sh
#   K8S_VERSION   — v1.35.0
#
# The cluster is single-node (see examples/kind-config.yaml).
# Deletes any existing cluster with the same name before creating.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="${1:-$("$SCRIPT_DIR/cluster-name.sh")}"
K8S_VERSION="${2:-v1.35.0}"
KIND_CONFIG="${SKILL_DIR}/examples/kind-config.yaml"

echo "==> Cluster name : $CLUSTER_NAME"
echo "==> Kubernetes   : $KIND_CONFIG (node image kindest/node:${K8S_VERSION})"

# Remove stale cluster if it exists
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "==> Existing cluster found — deleting first"
  kind delete cluster --name "$CLUSTER_NAME"
fi

kind create cluster \
  --name "$CLUSTER_NAME" \
  --config "$KIND_CONFIG" \
  --image "kindest/node:${K8S_VERSION}" \
  --wait 120s

echo "==> Cluster ready: $CLUSTER_NAME"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
