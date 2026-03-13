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

### Claude Code (as a Plugin — recommended)

Add the marketplace and install:

```bash
claude plugin marketplace add zarcen/ai-persona
claude plugin install k8s-operator@ai-persona
```

Or install the skill directory manually:

```bash
mkdir -p .claude/skills/k8s-operator/references
curl -o .claude/skills/k8s-operator/SKILL.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/SKILL.md
curl -o .claude/skills/k8s-operator/references/crd-design.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/crd-design.md
curl -o .claude/skills/k8s-operator/references/reconciler-patterns.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/reconciler-patterns.md
curl -o .claude/skills/k8s-operator/references/client-go.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/client-go.md
curl -o .claude/skills/k8s-operator/references/testing.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/testing.md
```

Or copy from a local clone:
```bash
cp -r skills/k8s-operator/ .claude/skills/k8s-operator/
```

### Cursor (as a Skill — recommended)

The agent sees the skill description and loads it on demand when your task is relevant.
Reference files are read progressively — only what's needed.

```bash
mkdir -p .cursor/skills/k8s-operator/references
curl -o .cursor/skills/k8s-operator/SKILL.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/SKILL.md
curl -o .cursor/skills/k8s-operator/references/crd-design.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/crd-design.md
curl -o .cursor/skills/k8s-operator/references/reconciler-patterns.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/reconciler-patterns.md
curl -o .cursor/skills/k8s-operator/references/client-go.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/client-go.md
curl -o .cursor/skills/k8s-operator/references/testing.md \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/skills/k8s-operator/references/testing.md
```

Or copy from a local clone:
```bash
cp -r skills/k8s-operator/ .cursor/skills/k8s-operator/
```

### Cursor (as a Rule — alternative)

Bundles everything into one `.mdc` file (~1100 lines), auto-injected on all `.go`/`.yaml` files:

```bash
mkdir -p .cursor/rules
curl -o .cursor/rules/k8s-operator.mdc \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/cursor-rules/k8s-operator.mdc
```

### Generic (any agent that reads markdown rules)

Copy `SKILL.md` and the `references/` folder to your agent's skills or rules directory.

---

## File Structure

```
k8s-operator/
├── SKILL.md                          # Main skill source (Cursor skill / Claude Code skill)
├── README.md                         # This file
└── references/
    ├── crd-design.md                 # CRD schema, validation, conversion webhooks
    ├── reconciler-patterns.md        # Finalizers, error handling, events, metrics
    ├── client-go.md                  # client-go API, indexers, dynamic client
    └── testing.md                    # envtest, Ginkgo, fake client, fuzz tests
```
