# ai-persona

A monorepo of reusable agent skills and MCPs for Claude Code, Cursor, and other AI coding agents.

---

## Skills

| Skill | Description | Install |
|-------|-------------|---------|
| [k8s-operator](skills/k8s-operator/) | Kubernetes operator development with kubebuilder — CRDs, reconcilers, client-go, testing | [README](skills/k8s-operator/README.md) |

> See each skill's README for detailed installation instructions.

---

## Install Overview

### Claude Code (as a Plugin — recommended)

Add the marketplace once, then install any skill by name:

```bash
claude plugin marketplace add zarcen/ai-persona
claude plugin install <skill-name>@ai-persona
```

### Claude Code (manual — curl)

Copy the skill's `SKILL.md` and `references/` directory into `.claude/skills/<skill-name>/`.
See each skill's README for exact commands.

### Cursor (as a Skill — recommended)

Copy the skill's `SKILL.md` and `references/` directory into `.cursor/skills/<skill-name>/`.
The agent sees the skill description and loads it on demand when your task is relevant.
See each skill's README for exact commands.

### Cursor (as a Rule — alternative)

Download the pre-built `.mdc` file from `cursor-rules/` into `.cursor/rules/`.
This bundles everything into one file, auto-injected on matching file patterns.
See each skill's README for exact commands.

### Generic (any agent that reads markdown)

Copy `SKILL.md` and the `references/` folder into your agent's skills or rules directory.

---

## Repo Structure

```
ai-persona/
├── .claude-plugin/              # Claude Code marketplace manifest
│   └── marketplace.json
├── skills/
│   └── <skill-name>/
│       ├── .claude-plugin/      # Per-skill plugin manifest (auto-generated)
│       │   └── plugin.json
│       ├── SKILL.md             # Source — frontmatter + instructions
│       ├── README.md            # Human-readable install guide
│       └── references/          # Deep-dive reference docs (loaded on demand)
├── cursor-rules/                # Built .mdc files (SKILL.md + references bundled)
├── scripts/
│   ├── build.sh                 # Regenerate cursor-rules/ and plugin manifests
│   └── validate.sh              # Lint frontmatter + check broken refs
└── .github/workflows/
    └── build.yml                # Auto-rebuild on push to main
```

---

## Adding a New Skill

```bash
# 1. Scaffold
mkdir -p skills/my-skill/references

# 2. Write the skill
#    skills/my-skill/SKILL.md       ← frontmatter (name, description, parameters) + main body
#    skills/my-skill/references/    ← optional deep-dive docs
#    skills/my-skill/README.md      ← human-readable install guide

# 3. Build (generates .mdc + plugin manifests)
./scripts/build.sh my-skill

# 4. Validate
./scripts/validate.sh my-skill

# 5. Commit (cursor-rules/ files are committed so curl installs work without a build step)
git add skills/my-skill cursor-rules/my-skill.mdc README.md
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
# Build all skills (generates .mdc + plugin manifests)
./scripts/build.sh

# Build a single skill
./scripts/build.sh k8s-operator

# Validate (frontmatter, references, built artifacts)
./scripts/validate.sh
```

CI (GitHub Actions) automatically rebuilds `cursor-rules/` and plugin manifests
on every push to `main`.
