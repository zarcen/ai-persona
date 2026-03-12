# k8s-operator Skill

An expert guide for building Kubernetes operators scaffolded with kubebuilder.

Covers:
- Project scaffolding with kubebuilder v4
- CRD schema design, validation markers, and versioning
- Reconciler patterns (finalizers, owned resources, error handling)
- client-go / controller-runtime client usage
- RBAC markers
- Controller testing with envtest + Ginkgo

---

## Installation

### Claude Code

```bash
# Install from marketplace (once published)
claude plugin install k8s-operator

# Or install locally from this directory
claude plugin install ./k8s-operator-skill/
```

### Cursor Agent

```bash
# One-liner install (single .mdc file, all references bundled inline)
mkdir -p .cursor/rules
curl -o .cursor/rules/k8s-operator.mdc \
  https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/k8s-operator.mdc
```

Or copy manually:
```bash
cp k8s-operator.mdc .cursor/rules/k8s-operator.mdc
```

### Generic (any agent that reads markdown rules)

Copy `SKILL.md` and the `references/` folder to your agent's rules directory.

---

## Configuration

Override default parameters by creating `.claude/skill-params.yaml` (Claude Code)
or `.cursor/skill-params.yaml` (Cursor) in your project root:

```yaml
k8s_operator:
  go_version: "1.22"
  controller_runtime_version: "v0.18"
  kubebuilder_version: "v4"
  k8s_version: "1.31"
  default_image_registry: "gcr.io/my-project"
  enable_webhooks: true
  enable_leader_election: true
  reconcile_timeout: "10m"
  requeue_after_error: "30s"
  max_concurrent_reconciles: 1
```

---

## File Structure

```
k8s-operator-skill/
├── SKILL.md                          # Main skill (Claude Code)
├── k8s-operator.mdc                  # Bundled single-file (Cursor)
├── README.md                         # This file
└── references/
    ├── crd-design.md                 # CRD schema, validation, conversion webhooks
    ├── reconciler-patterns.md        # Finalizers, error handling, events, metrics
    ├── client-go.md                  # client-go API, indexers, dynamic client
    └── testing.md                    # envtest, Ginkgo, fake client, fuzz tests
```
