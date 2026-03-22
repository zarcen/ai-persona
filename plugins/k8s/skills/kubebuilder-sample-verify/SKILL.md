---
name: kubebuilder-sample-verify
description: >
  Verifies that all kubebuilder CR sample manifests in config/samples/ are valid against
  the current CRD schemas. Detects kubebuilder scaffold projects, spins up an ephemeral
  kind cluster named kind-<repo>-<hash>, installs CRDs from this repo, applies every sample,
  and reports API type errors or schema drift. Use when asked to validate samples, test CR
  examples, check for outdated manifests, or confirm a kubebuilder project's sample health.
parameters:
  samples_dir: "config/samples"
  keep_cluster: false
  k8s_version: "v1.35.0"
  kind_version: "v0.31.0"
---

# Kubebuilder Sample Verification Skill

You are an expert at validating kubebuilder project samples against live CRD schemas.
When asked to verify, validate, or test CR samples in a kubebuilder project, follow
these steps exactly. Use the scripts in `scripts/` to run verification and the examples
in `examples/` as references for expected output and kind configuration.

## Parameters

Override defaults in `.claude/skill-params.yaml` or `.cursor/skill-params.yaml`:

```yaml
# skill-params.yaml
kubebuilder_sample_verify:
  samples_dir: "config/samples"     # where to find CR YAML examples
  keep_cluster: false               # if true, leave the kind cluster running after verification
  k8s_version: "v1.35.0"           # Kubernetes version for the kind node image
  kind_version: "v0.31.0"          # kind CLI version to require
```

---

## Step 1 — Detect a Kubebuilder Project

Before doing anything else, confirm the current directory is a kubebuilder scaffold.
Check for all of the following:

```bash
test -f PROJECT          # kubebuilder PROJECT manifest (definitive marker)
test -d config/crd       # generated CRD manifests directory
test -d config/samples   # sample CRs (or the configured samples_dir)
test -f Makefile && grep -q "controller-gen" Makefile
```

If none of these exist, **stop** and tell the user:
> "This directory does not look like a kubebuilder project. I expected a `PROJECT` file,
> `config/crd/`, and `config/samples/` to be present."

If present, read `PROJECT` and report:
```bash
cat PROJECT
```
Extract `domain`, `repo`, and all `resources[].kind` values for context.

---

## Step 2 — Discover Sample Manifests

Find all YAML files under the configured `samples_dir` (default: `config/samples`),
excluding `kustomization.yaml` itself and kustomize patches prefixed with `_`:

```bash
SAMPLES_DIR="${SAMPLES_DIR:-config/samples}"
mapfile -t ALL_YAML < <(
  find "$SAMPLES_DIR" -maxdepth 1 -name "*.yaml" \
    -not -name "kustomization.yaml" \
    -not -name "_*" \
  | sort
)
```

If no YAML files are found at all, report:
> "No sample manifests found in `config/samples/`. Nothing to verify."

List the discovered files and the `apiVersion` + `kind` of each one:

```bash
for f in "${ALL_YAML[@]}"; do
  echo "--- $f"
  grep -E "^(apiVersion|kind):" "$f" | head -2
done
```

---

## Step 2b — Check for kustomization.yaml

Check whether `${SAMPLES_DIR}/kustomization.yaml` exists:

```bash
KUSTOMIZATION="${SAMPLES_DIR}/kustomization.yaml"
```

**If it exists**, extract the `resources:` list and compare against discovered YAML files.
Use `scripts/check-kustomization.sh` or the inline logic below:

```bash
# Parse resources listed in kustomization.yaml (relative names, strip leading "- ")
mapfile -t KUSTOMIZE_LISTED < <(
  grep -E '^\s*-\s+\S+\.yaml' "$KUSTOMIZATION" \
  | sed 's/^\s*-\s*//' \
  | sed "s|^|${SAMPLES_DIR}/|"
  | sort
)

# Find YAML files present on disk but absent from kustomization.yaml
MISSING=()
for F in "${ALL_YAML[@]}"; do
  BASENAME=$(basename "$F")
  if ! grep -qE "^\s*-\s+${BASENAME}\s*$" "$KUSTOMIZATION"; then
    MISSING+=("$F")
  fi
done
```

**If `MISSING` is non-empty**, warn the user:

```
WARNING: The following YAML files exist in config/samples/ but are NOT listed
in kustomization.yaml. They will be skipped if kustomization is used:

  - config/samples/apps_v1alpha1_myapp_new.yaml
  - config/samples/apps_v1beta1_myapp.yaml

Options:
  [K] Use kustomization.yaml as-is (skip the missing files)
  [A] Also validate the missing files individually (in addition to kustomization)
  [Q] Quit — I'll update kustomization.yaml first
```

Ask the user to choose, then proceed accordingly.

**If `MISSING` is empty**, use kustomization directly without prompting.

**If `kustomization.yaml` does not exist**, fall back to validating each YAML file
individually (original behavior).

---

## Step 3 — Determine the Cluster Name

Use `scripts/cluster-name.sh` to produce a deterministic cluster name, or run inline:

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
REPO_SLUG=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-20 | sed 's/-$//')
GIT_HASH=$(git rev-parse --short=6 HEAD 2>/dev/null || echo "$(pwd)" | md5sum | cut -c1-6)
CLUSTER_NAME="kind-${REPO_SLUG}-${GIT_HASH}"
echo "Cluster name: $CLUSTER_NAME"
```

Tell the user the cluster name before creating it.

---

## Step 4 — Prerequisite Checks

Verify required tools are installed:

```bash
kind version   || { echo "ERROR: kind not found. Install: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"; exit 1; }
kubectl version --client || { echo "ERROR: kubectl not found."; exit 1; }
make --version || { echo "ERROR: make not found."; exit 1; }
```

Check that the cluster name doesn't already exist:

```bash
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "WARNING: Cluster $CLUSTER_NAME already exists. Deleting it first."
  kind delete cluster --name "$CLUSTER_NAME"
fi
```

---

## Step 5 — Regenerate CRD Manifests

Always regenerate CRDs from source before installing to catch schema drift:

```bash
make manifests 2>&1
```

If `make manifests` fails (e.g. controller-gen not installed), fall back to existing
manifests in `config/crd/bases/` and warn the user:
> "Warning: `make manifests` failed. Using existing CRD manifests — schema may be stale."

---

## Step 6 — Create the Ephemeral kind Cluster

Use `scripts/create-cluster.sh` or run directly:

```bash
kind create cluster \
  --name "$CLUSTER_NAME" \
  --config examples/kind-config.yaml \
  --image "kindest/node:${K8S_VERSION:-v1.35.0}" \
  --wait 120s
```

See `examples/kind-config.yaml` for the standard single-node config used by this skill.

Set the kubeconfig context:

```bash
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
```

Use `--context "kind-${CLUSTER_NAME}"` on every subsequent `kubectl` call to avoid
accidentally targeting another cluster.

---

## Step 7 — Install CRDs

```bash
make install 2>&1

# Verify CRDs registered
kubectl get crds \
  --context "kind-${CLUSTER_NAME}" \
  -o custom-columns="NAME:.metadata.name,VERSION:.spec.versions[*].name"
```

If no CRDs appear, report an error and skip to cleanup.

---

## Step 8 — Apply Samples and Collect Results

Use `scripts/verify-samples.sh`. It automatically detects `kustomization.yaml` and
applies the correct strategy based on the decision made in Step 2b.

### 8a — kustomization.yaml present (user chose K or A)

Run the kustomized output through a single server-side dry-run:

```bash
OUTPUT=$(kubectl kustomize "${SAMPLES_DIR}" \
  | kubectl apply -f - \
    --context "kind-${CLUSTER_NAME}" \
    --dry-run=server \
    2>&1)
```

If the user chose **A** (also validate missing files), additionally run each missing
file individually per 8b and append results to the report.

### 8b — No kustomization.yaml, or validating missing files individually

Apply each target file individually to get per-file error details:

```bash
PASS=()
FAIL=()
declare -A ERROR_MAP

for SAMPLE in "${TARGETS[@]}"; do
  OUTPUT=$(kubectl apply -f "$SAMPLE" \
    --context "kind-${CLUSTER_NAME}" \
    --dry-run=server \
    2>&1)
  if [[ $? -eq 0 ]]; then
    PASS+=("$SAMPLE")
  else
    FAIL+=("$SAMPLE")
    ERROR_MAP["$SAMPLE"]="$OUTPUT"
  fi
done
```

`--dry-run=server` catches:
- Missing required fields
- Invalid enum values
- Wrong field types (string vs integer, etc.)
- Unknown fields (when `x-kubernetes-preserve-unknown-fields: false`)
- Deprecated or removed apiVersions

---

## Step 9 — Report Results

Print a structured report (see `examples/report-pass.txt` and `examples/report-fail.txt`
for expected output formats):

```
=== Kubebuilder Sample Verification Report ===
Cluster:   kind-<name>
CRDs:      <N> installed
Samples:   <total> checked

PASSED (<n>):
  ✓ config/samples/apps_v1alpha1_myapp.yaml
  ...

FAILED (<n>):
  ✗ config/samples/apps_v1beta1_myapp.yaml
    Error: apps.example.com/v1beta1, Kind=MyApp: spec.replicas: Invalid value: "string": must be integer

=== Summary ===
```

Then give an **analysis** for each failure:

| Sample | Kind | Error | Likely Cause | Suggested Fix |
|--------|------|-------|--------------|---------------|
| `apps_v1beta1_myapp.yaml` | MyApp/v1beta1 | `spec.replicas: must be integer` | Field type changed from string to int32 | Change `replicas: "2"` → `replicas: 2` |

Common failure patterns to recognize and explain:

| Error pattern | Likely cause |
|---------------|--------------|
| `unknown field` | Field removed or renamed in CRD; sample is outdated |
| `required field missing` | New required field added to CRD without updating sample |
| `Invalid value … must be <type>` | Field type changed (e.g. string→int) |
| `no kind "X" registered` | CRD not installed; apiVersion mismatch |
| `strict decoding error` | Extra fields not allowed by schema |
| `spec.foo: Forbidden` | Field moved to status or removed |

---

## Step 10 — Cleanup

Unless `keep_cluster: true`:

```bash
kind delete cluster --name "$CLUSTER_NAME"
echo "Cluster $CLUSTER_NAME deleted."
```

If `keep_cluster: true`, tell the user:
> "Cluster `$CLUSTER_NAME` is still running. To delete it manually:
> `kind delete cluster --name $CLUSTER_NAME`"

---

## Key Rules

- **Always use `--dry-run=server`** — never mutate objects in the verification cluster.
- **Always delete the cluster** on exit unless `keep_cluster: true` — clusters are ephemeral.
- **Always regenerate CRDs** with `make manifests` before installing to catch schema drift.
- **Scope all kubectl calls** with `--context kind-<cluster>` — never target other clusters.
- **Report per-file** — do not batch-apply; individual errors are more actionable.
- **Do not modify samples automatically** — report errors and explain the fix; let the user decide.

---

## Reference Files

Load these when you need deeper coverage:

- `references/kind-setup.md` — kind cluster config, node images, networking, multi-node setups
- `references/sample-validation.md` — validation error taxonomy, kustomize overlays, multi-version samples
