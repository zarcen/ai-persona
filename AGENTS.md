# AGENTS.md — Contributor Guide for AI Coding Agents

This file tells AI coding agents (Claude Code, Cursor, etc.) how to work with this repo.

---

## Repo Purpose

This is a monorepo of portable **agent skills** and **MCPs** (Model Context Protocol servers).
Skills are markdown-based instruction sets that teach AI agents domain expertise.
Each skill is authored as a `SKILL.md` with optional `references/` docs. The repo is also
a Claude Code plugin (`.claude-plugin/`) and builds `.mdc` Cursor rule files.

---

## Repo Layout

```
ai-persona/
├── AGENTS.md                        ← You are here
├── README.md                        ← Public catalog + install instructions
├── .claude-plugin/                  ← Claude Code marketplace manifest
│   └── marketplace.json
├── scripts/
│   ├── build.sh                     ← Bundles SKILL.md + references → .mdc
│   └── validate.sh                  ← Lints frontmatter, checks refs, verifies cursor-rules/
├── skills/
│   └── <skill-name>/
│       ├── .claude-plugin/           ← Per-skill plugin manifest (auto-generated)
│       │   └── plugin.json
│       ├── SKILL.md                 ← Source: frontmatter + instructions
│       ├── README.md                ← Human-readable description + install guide
│       ├── references/              ← Deep-dive reference docs (bundled into .mdc)
│       │   ├── topic-a.md
│       │   └── topic-b.md
├── cursor-rules/                    ← Built .mdc files (committed for curl installs)
│   └── <skill-name>.mdc
├── mcps/                            ← MCP servers (coming soon)
│   └── <mcp-name>/
│       ├── README.md
│       ├── server.py / index.ts     ← MCP server implementation
│       └── mcp.json                 ← MCP manifest
└── .github/workflows/
    └── build.yml                    ← CI: build + validate + auto-commit cursor-rules/
```

---

## Adding a New Skill

### 1. Scaffold the directory

```bash
SKILL_NAME="my-new-skill"
mkdir -p "skills/${SKILL_NAME}/references"
```

### 2. Write `skills/<name>/SKILL.md`

This is the source of truth. It **must** have YAML frontmatter with at least `name` and `description`:

```yaml
---
name: my-new-skill
description: >
  One paragraph that tells the agent WHEN to activate this skill.
  Be specific about trigger keywords, file types, and use cases.
  The more precise, the better the agent triggers on it.
parameters:
  some_param: "default_value"
  another_param: true
globs:                         # optional — file patterns that auto-trigger this skill
  - "**/*.py"
  - "**/Dockerfile"
---

# My New Skill

You are an expert in <domain>. Follow these guidelines when ...

## 1. Section Title

<instructions, code examples, rules>

## Reference Files

Load these when you need deeper coverage:

- `references/topic-a.md` — description
- `references/topic-b.md` — description
```

**Frontmatter rules:**
- `name` — lowercase, kebab-case, must match the directory name
- `description` — use YAML folded scalar (`>`) for multi-line; this becomes the `.mdc` trigger text
- `parameters` — optional key-value pairs users can override in their project
- `globs` — optional list of file glob patterns; if omitted, `build.sh` defaults to `**/*.go` and `**/*.yaml`

**Body rules:**
- Write in second person ("You are an expert...", "Always use...", "Never do...")
- Use numbered sections for major topics
- Include concrete code examples — agents learn best from examples
- Reference deep-dive docs as `references/<filename>.md`
- End with a "Reference Files" section listing all references with one-line descriptions

### 3. Write reference docs (optional)

Place detailed reference material in `skills/<name>/references/*.md`. These get bundled
inline into the `.mdc` during build. Each reference file should be self-contained with
its own title and table of contents.

Keep individual reference files under ~300 lines. Split large topics into multiple files.

### 4. Write `skills/<name>/README.md`

A human-readable description of the skill for GitHub browsing. Include:
- What the skill covers
- Installation instructions (Cursor curl one-liner, Claude Code install)
- Configuration / parameter overrides
- File structure listing

**Claude Code plugin install command format:**
The syntax is `claude plugin install <plugin-name>@<marketplace-name>`.
The marketplace name is `ai-persona` and the plugin name matches the skill name.
For example, for a skill named `my-new-skill`:
```bash
claude plugin marketplace add zarcen/ai-persona
claude plugin install my-new-skill@ai-persona
```

### 5. Build

```bash
./scripts/build.sh my-new-skill
```

This produces:
- `cursor-rules/my-new-skill.mdc` — built Cursor rule file
- `skills/my-new-skill/.claude-plugin/plugin.json` — Claude Code plugin manifest
- `.claude-plugin/marketplace.json` — updated marketplace catalog

### 6. Validate

```bash
./scripts/validate.sh my-new-skill
```

All checks must pass: frontmatter fields present, reference links valid, cursor-rules files exist.

### 7. Update README.md

Add a row to the skills table in the root `README.md`:

```markdown
| [my-new-skill](skills/my-new-skill/) | One-line description | [README](skills/my-new-skill/README.md) |
```

Skill-specific installation commands belong in the skill's own `README.md`, not in the root README.
The root README only has generic install patterns (marketplace add, curl overview) and links to each skill's README.

### 8. Commit

```bash
git add skills/my-new-skill/ cursor-rules/my-new-skill.mdc .claude-plugin/marketplace.json README.md
git commit -m "feat: add my-new-skill"
```

Commit `cursor-rules/` and `.claude-plugin/` files so curl installs and plugin installs work without a build step.
CI will also auto-rebuild on push to main as a safety net.

---

## Adding a New MCP

> MCPs are under `mcps/` — this section is a placeholder for the upcoming structure.

### 1. Scaffold

```bash
MCP_NAME="my-mcp"
mkdir -p "mcps/${MCP_NAME}"
```

### 2. Create the MCP server

Implement the server in `mcps/<name>/server.py` (Python) or `mcps/<name>/index.ts` (TypeScript).

### 3. Create `mcps/<name>/mcp.json`

```json
{
  "name": "my-mcp",
  "description": "What this MCP does",
  "version": "0.1.0",
  "transport": "stdio",
  "command": "python",
  "args": ["server.py"]
}
```

### 4. Create `mcps/<name>/README.md`

Document setup, dependencies, and usage.

### 5. Update root README.md

Add an entry to the MCPs table (create the table if it doesn't exist yet).

---

## Build System

### `scripts/build.sh`

- Extracts frontmatter from `SKILL.md` (handles YAML folded/block scalars)
- Generates `.mdc` Cursor rule file: frontmatter (`description`, `globs`, `alwaysApply`) + body + inlined references
- Generates `skills/<name>/.claude-plugin/plugin.json` per-skill plugin manifest
- Regenerates `.claude-plugin/marketplace.json` marketplace catalog
- Outputs to `cursor-rules/<name>.mdc`

### `scripts/validate.sh`

Checks:
- `SKILL.md` exists with required `name` and `description` frontmatter
- All `references/*.md` files exist
- Cross-references in `SKILL.md` (e.g. `references/foo.md`) resolve to real files
- `cursor-rules/<name>.mdc` exists and is non-empty

### CI (`.github/workflows/build.yml`)

On every push/PR to `main`:
1. Builds all skills
2. Validates all skills
3. On main branch pushes: auto-commits rebuilt `cursor-rules/` files with `[skip ci]`

---

## Conventions

- **Skill names**: lowercase kebab-case (e.g. `k8s-operator`, `react-testing`)
- **One skill per directory**: never nest skills
- **Commit cursor-rules/**: always commit built `.mdc` files so curl installs work without CI
- **No secrets**: never put API keys, tokens, or credentials in skill files
- **Idempotent builds**: running `build.sh` twice produces identical output
- **Test locally**: always run `validate.sh` before pushing

---

## Quick Reference

| Task | Command |
|------|---------|
| Build all skills | `./scripts/build.sh` |
| Build one skill | `./scripts/build.sh <name>` |
| Validate all | `./scripts/validate.sh` |
| Validate one | `./scripts/validate.sh <name>` |
| Install in Claude Code (plugin) | `/plugin marketplace add zarcen/ai-persona` then `/plugin install <name>@ai-persona` |
| Install in Claude Code (manual) | `cp -r skills/<name>/ .claude/skills/<name>/` |
| Install in Cursor (skill) | `cp -r skills/<name>/ .cursor/skills/<name>/` |
| Install in Cursor (rule) | `curl -o .cursor/rules/<name>.mdc https://raw.githubusercontent.com/zarcen/ai-persona/main/cursor-rules/<name>.mdc` |
