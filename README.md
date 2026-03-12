# ai-persona

A monorepo of reusable agent skills and MCPs for Claude Code, Cursor, and other AI coding agents.

---

## Skills

| Skill | Description | Install |
|-------|-------------|---------|
| [k8s-operator](skills/k8s-operator/) | Kubernetes operator development with kubebuilder — CRDs, reconcilers, client-go, testing | [↓ install](#install) |

---

## Install

### Claude Code (as a Plugin — recommended)

Add the marketplace and install:

```bash
claude plugin marketplace add zarcen/ai-persona
claude plugin install ai-persona@<skill_name>
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

### Cursor (as a Skill — recommended)

Install the skill directory so the agent loads it on demand:

```bash
# k8s-operator
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

### Cursor (as a Rule — alternative)

Bundles everything into one file, auto-injected on all `.go`/`.yaml` files:

```bash
mkdir -p .cursor/rules
curl -o .cursor/rules/k8s-operator.mdc \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/cursor-rules/k8s-operator.mdc
```

---

## Repo Structure

```
ai-persona/
├── .claude-plugin/              # Claude Code plugin + marketplace manifests
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md             # Source — frontmatter + instructions
│       └── references/          # Deep-dive reference docs (loaded on demand)
├── cursor-rules/                # Built .mdc files (SKILL.md + references bundled)
├── scripts/
│   ├── build.sh                 # Regenerate all cursor-rules/ files
│   └── validate.sh              # Lint frontmatter + check broken refs
└── .github/workflows/
    └── build.yml                # Auto-rebuild cursor-rules/ on push to main
```

---

## Adding a New Skill

```bash
# 1. Scaffold
mkdir -p skills/my-skill/references

# 2. Write the skill
#    skills/my-skill/SKILL.md       ← frontmatter (name, description, parameters) + main body
#    skills/my-skill/references/    ← optional deep-dive docs

# 3. Build
./scripts/build.sh my-skill

# 4. Validate
./scripts/validate.sh my-skill

# 5. Commit (cursor-rules/ files are committed so curl installs work without a build step)
git add skills/my-skill cursor-rules/my-skill.mdc
git commit -m "feat: add my-skill"
```

### SKILL.md frontmatter format

```yaml
---
name: my-skill
description: >
  One-paragraph description used as the agent trigger.
  Be specific about when to use this skill. The more
  precise, the better the agent will trigger on it.
parameters:
  some_param: "default_value"
  another_param: true
---
```

---

## Adding an MCP

MCPs live under `mcps/` (coming soon). Each MCP has its own directory with a `README.md`,
server implementation, and any required config.

---

## Local Development

```bash
# Build all skills
./scripts/build.sh

# Build a single skill
./scripts/build.sh k8s-operator

# Validate
./scripts/validate.sh
```

CI (GitHub Actions) automatically rebuilds and commits `cursor-rules/` on every push to `main`.
