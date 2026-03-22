# k8s Plugin

Kubernetes development skills for AI coding agents — operators, controllers, CRDs, client-go, and envtest-based testing with kubebuilder and controller-runtime.

## Skills

| Skill | Description |
|-------|-------------|
| [k8s-operator](skills/k8s-operator/) | Expert guide for building Kubernetes operators: CRD design, reconciler patterns, client-go usage, RBAC markers, webhooks, envtest testing |

---

## Installation

### Claude Code (Plugin — recommended)

```bash
claude plugin marketplace add zarcen/ai-persona
claude plugin install k8s@ai-persona
```

### Claude Code (manual)

```bash
# Download a skill folder and place it under .claude/skills/
gh repo clone zarcen/ai-persona /tmp/ai-persona && cp -r /tmp/ai-persona/plugins/k8s/skills/<skill-name> .claude/skills/
```

### Cursor (Marketplace Plugin — recommended)

Install via the Cursor Marketplace using the `.cursor-plugin/marketplace.json` in this repo.

### Cursor (manual)

```bash
# Download a skill folder and place it under .cursor/skills/
gh repo clone zarcen/ai-persona /tmp/ai-persona && cp -r /tmp/ai-persona/plugins/k8s/skills/<skill-name> .cursor/skills/
```

### Codex

```bash
ln -s ~/.codex/ai-persona/plugins/k8s/skills ~/.agents/skills/k8s
```

---

## File Structure

```
k8s/
├── .claude-plugin/plugin.json            # Claude Code manifest
├── .cursor-plugin/plugin.json            # Cursor marketplace manifest
├── assets/logo.svg
└── skills/
    └── k8s-operator/
        ├── SKILL.md                      # Main skill (frontmatter + instructions)
        └── references/
            ├── crd-design.md             # CRD schema, validation, conversion webhooks
            ├── reconciler-patterns.md    # Finalizers, error handling, events, metrics
            ├── client-go.md              # client-go API, indexers, dynamic client
            └── testing.md               # envtest, Ginkgo, fake client, fuzz tests
```
