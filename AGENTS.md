# AGENTS.md — Contributor Guide for AI Coding Agents

This file tells AI coding agents (Claude Code, Cursor, etc.) how to work with this repo.

---

## Repo Purpose

This is a monorepo of portable **agent skills** and **MCPs** (Model Context Protocol servers).
Skills are markdown-based instruction sets that teach AI agents domain expertise.
Each skill is authored as a `SKILL.md` with optional `references/` docs, then built into
a single `.mdc` file for easy installation in Cursor or Claude Code.

---

## Repo Layout

```
ai-persona/
├── AGENTS.md                        ← You are here
├── README.md                        ← Public catalog + install instructions
├── scripts/
│   ├── build.sh                     ← Bundles SKILL.md + references → .mdc
│   └── validate.sh                  ← Lints frontmatter, checks refs, verifies dist/
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md                 ← Source: frontmatter + instructions
│       ├── README.md                ← Human-readable description + install guide
│       ├── references/              ← Deep-dive reference docs (bundled into .mdc)
│       │   ├── topic-a.md
│       │   └── topic-b.md
│       └── dist/
│           └── <skill-name>.mdc     ← Built artifact (committed for curl installs)
├── dist/                            ← Flat mirror of all .mdc files (stable curl URLs)
│   └── <skill-name>.mdc
├── mcps/                            ← MCP servers (coming soon)
│   └── <mcp-name>/
│       ├── README.md
│       ├── server.py / index.ts     ← MCP server implementation
│       └── mcp.json                 ← MCP manifest
└── .github/workflows/
    └── build.yml                    ← CI: build + validate + auto-commit dist/
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

### 5. Build

```bash
./scripts/build.sh my-new-skill
```

This produces:
- `skills/my-new-skill/dist/my-new-skill.mdc` — per-skill artifact
- `dist/my-new-skill.mdc` — flat mirror for curl installs

### 6. Validate

```bash
./scripts/validate.sh my-new-skill
```

All checks must pass: frontmatter fields present, reference links valid, dist files exist.

### 7. Update README.md

Add a row to the skills table in the root `README.md`:

```markdown
| [my-new-skill](skills/my-new-skill/) | One-line description | [↓ curl](#install) |
```

Add curl install command under the `### Cursor Agent` section:

```bash
# my-new-skill
curl -o .cursor/rules/my-new-skill.mdc \
  https://raw.githubusercontent.com/zarcen/ai-persona/main/dist/my-new-skill.mdc
```

### 8. Commit

```bash
git add skills/my-new-skill/ dist/my-new-skill.mdc README.md
git commit -m "feat: add my-new-skill"
```

Commit `dist/` files so curl installs work without a build step.
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
- Copies to both `skills/<name>/dist/` and root `dist/`

### `scripts/validate.sh`

Checks:
- `SKILL.md` exists with required `name` and `description` frontmatter
- All `references/*.md` files exist
- Cross-references in `SKILL.md` (e.g. `references/foo.md`) resolve to real files
- `dist/<name>.mdc` exists and is non-empty
- Root `dist/<name>.mdc` mirror exists

### CI (`.github/workflows/build.yml`)

On every push/PR to `main`:
1. Builds all skills
2. Validates all skills
3. On main branch pushes: auto-commits rebuilt `dist/` files with `[skip ci]`

---

## Conventions

- **Skill names**: lowercase kebab-case (e.g. `k8s-operator`, `react-testing`)
- **One skill per directory**: never nest skills
- **Commit dist/**: always commit built `.mdc` files so curl installs work without CI
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
| Install in Cursor | `curl -o .cursor/rules/<name>.mdc https://raw.githubusercontent.com/zarcen/ai-persona/main/dist/<name>.mdc` |
