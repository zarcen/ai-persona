# ai-persona

A monorepo of reusable agent skills and MCPs for Claude Code, Cursor, and other AI coding agents.

---

## Skills

| Skill | Description | Install |
|-------|-------------|---------|
| [k8s-operator](skills/k8s-operator/) | Kubernetes operator development with kubebuilder — CRDs, reconcilers, client-go, testing | [↓ curl](#install) |

---

## Install

### Cursor Agent

```bash
mkdir -p .cursor/rules

# k8s-operator
curl -o .cursor/rules/k8s-operator.mdc \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/dist/k8s-operator.mdc
```

### Claude Code

```bash
# k8s-operator
claude plugin install https://github.com/zarcen/ai-persona/tree/main/skills/k8s-operator
```

---

## Repo Structure

```
ai-persona/
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md          # Source — frontmatter + instructions
│       ├── references/       # Deep-dive reference docs (loaded on demand)
│       └── dist/
│           └── <name>.mdc    # Built artifact (SKILL.md + references bundled)
├── dist/                     # Flat mirror of all .mdc files (stable curl URLs)
├── scripts/
│   ├── build.sh              # Regenerate all dist/ files
│   └── validate.sh           # Lint frontmatter + check broken refs
└── .github/workflows/
    └── build.yml             # Auto-rebuild dist/ on push to main
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

# 5. Commit (dist/ files are committed so curl installs work without a build step)
git add skills/my-skill dist/my-skill.mdc
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

CI (GitHub Actions) automatically rebuilds and commits `dist/` on every push to `main`.
