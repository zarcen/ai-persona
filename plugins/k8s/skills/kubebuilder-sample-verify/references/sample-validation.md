# Sample Validation Reference

Detailed guidance on validation error taxonomy, multi-version samples, and kustomize overlays.

---

## Validation Error Taxonomy

### 1. Type Mismatch

```
spec.replicas: Invalid value: "string": spec.replicas in body must be of type integer: "string"
```

**Cause:** A field's Go type changed in the CRD (e.g. `string` → `int32`).
**Fix:** Update the sample value to match the new type.

```yaml
# Before (wrong — string)
spec:
  replicas: "3"

# After (correct — integer)
spec:
  replicas: 3
```

---

### 2. Required Field Missing

```
spec.image: Required value
```

**Cause:** A new required field was added to the CRD spec without a `+kubebuilder:default` marker,
and the sample was not updated.
**Fix:** Add the missing field to the sample, or add `+optional` / `+kubebuilder:default` to the type.

---

### 3. Unknown Field (strict validation)

```
spec.deprecatedField: Forbidden: unknown field
```

**Cause:** A field was removed from the CRD schema. By default kubebuilder generates CRDs with
`x-kubernetes-preserve-unknown-fields: false`, so unknown fields are rejected.
**Fix:** Remove the stale field from the sample.

---

### 4. Enum Violation

```
spec.phase: Unsupported value: "active": supported values: "Pending", "Running", "Failed"
```

**Cause:** The `+kubebuilder:validation:Enum` marker was updated and the sample uses an old value.
**Fix:** Update the sample to use a supported enum value.

---

### 5. CRD Not Registered

```
no matches for kind "MyApp" in version "apps.example.com/v1alpha1"
```

**Cause:** The CRD was not installed, or the `apiVersion`/`kind` in the sample does not match
what was installed.
**Fix:** Re-run `make install` and confirm with `kubectl get crds --context kind-$CLUSTER`.
Check the sample's `apiVersion` matches the CRD group/version.

---

### 6. CEL Validation Failure (Kubernetes 1.25+)

```
spec: Invalid value: ...: <field> failed rule: self.minReplicas <= self.maxReplicas
```

**Cause:** A `+kubebuilder:validation:XValidation` CEL rule is violated by the sample values.
**Fix:** Adjust the sample values to satisfy the CEL expression, or review the rule in the type definition.

---

## Multi-Version Samples

When a CRD has multiple stored versions (e.g. `v1alpha1` and `v1beta1`), validate samples
for each version:

```bash
find config/samples -name "*.yaml" | xargs grep "apiVersion:" | sort
```

Ensure at least one sample per version. The `hub` version (served + storage) must always
have a sample. Conversion webhook samples should be tested with both versions present.

---

## Kustomize Overlays

Some projects use `config/samples/kustomization.yaml` to compose samples.
To validate the composed output rather than individual files:

```bash
# Build and pipe to kubectl dry-run
kubectl kustomize config/samples \
  | kubectl apply -f - \
    --context "kind-${CLUSTER_NAME}" \
    --dry-run=server
```

Exclude patch files (prefixed with `_`) from direct validation — they are not standalone CRs.

---

## Namespace Considerations

If your CRs target a specific namespace, create it first:

```bash
kubectl create namespace my-system --context "kind-${CLUSTER_NAME}" 2>/dev/null || true
```

Or patch the sample's `metadata.namespace` for validation:

```bash
kubectl apply -f sample.yaml \
  --context "kind-${CLUSTER_NAME}" \
  --dry-run=server \
  --namespace default
```

---

## Cluster-Scoped vs Namespace-Scoped Resources

Cluster-scoped CRDs (`+kubebuilder:resource:scope=Cluster`) must not have a `namespace` field
in their sample `metadata`. Namespace-scoped CRDs should always include `metadata.namespace`.

Check the scope:
```bash
kubectl get crd myapps.apps.example.com \
  --context "kind-${CLUSTER_NAME}" \
  -o jsonpath='{.spec.scope}'
```

---

## Defaulting Webhooks and Dry-Run

If the operator uses defaulting webhooks (`+kubebuilder:webhook:defaulting`), the webhook is
NOT running in the kind cluster during this verification. Fields that rely on webhook defaults
must be explicitly set in samples, or the dry-run may report them as missing required fields.

To test webhook defaulting, you must deploy the operator into the kind cluster:
```bash
make deploy IMG=<your-image>
```
This is out of scope for the `kubebuilder-sample-verify` skill's default mode; it only
performs schema validation without a running controller.
