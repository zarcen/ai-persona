# kind Setup Reference

Deep-dive on kind cluster configuration for kubebuilder sample verification.

---

## Node Images

Pin node images to a specific Kubernetes patch version for reproducibility.
Find available images at: https://github.com/kubernetes-sigs/kind/releases

```bash
# v1.35.x (default for this skill)
kindest/node:v1.35.0

# Older versions for testing backward compat
kindest/node:v1.32.0
kindest/node:v1.30.0
```

To use a different version:
```bash
kind create cluster --name "$CLUSTER_NAME" --image kindest/node:v1.32.0
```

---

## Cluster Config Options

### Minimal (default — used by this skill)

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
```

### With extra port mappings (for webhook testing)

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 9443
        hostPort: 9443
        protocol: TCP
```

### Multi-node (for HA testing — not needed for sample validation)

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

### Enable feature gates

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
featureGates:
  CustomResourceValidationExpressions: true
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            feature-gates: "CustomResourceValidationExpressions=true"
```

---

## Context Management

kind clusters register contexts as `kind-<cluster-name>`.
Always pass `--context` explicitly to avoid targeting the wrong cluster:

```bash
# Set once for the session
export KUBECONFIG_CONTEXT="kind-${CLUSTER_NAME}"

# Use explicitly on every kubectl call
kubectl get crds --context "kind-${CLUSTER_NAME}"
kubectl apply -f sample.yaml --context "kind-${CLUSTER_NAME}" --dry-run=server
```

To switch context globally (not recommended when other clusters exist):
```bash
kubectl config use-context "kind-${CLUSTER_NAME}"
```

---

## Cleanup

```bash
# Delete a specific cluster
kind delete cluster --name "$CLUSTER_NAME"

# Delete all kind clusters (destructive — use carefully)
kind get clusters | xargs -I{} kind delete cluster --name {}
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `node(s) are not ready` after `--wait 120s` | Docker resource limit hit | Increase Docker memory to ≥4 GB |
| `cannot connect to the Docker daemon` | Docker not running | `sudo systemctl start docker` |
| `cluster already exists` | Leftover from prior run | `kind delete cluster --name $NAME` |
| CRDs not showing after `make install` | Wrong kubeconfig context | Verify `--context kind-$CLUSTER_NAME` |
| `exec: kind: not found` | kind not in PATH | `export PATH="$PATH:$(go env GOPATH)/bin"` |
