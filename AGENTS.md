# AGENTS.md — Contributor Guide for AI Coding Agents

This file tells AI coding agents (Claude Code, Cursor, Codex, etc.) how to work with this repo.

---

## Repo Purpose

This is **ai-persona** — a marketplace of portable agent plugins, each containing skills, hooks,
and rules that teach AI agents domain expertise. Skills are markdown-based instruction sets
(`SKILL.md`) with optional `references/` deep-dive docs.

---

## Repo Layout

```
ai-persona/
├── AGENTS.md                            ← You are here
├── README.md                            ← Public catalog + install instructions
├── .claude-plugin/                      ← GENERATED — Claude Code marketplace catalog
│   └── marketplace.json
├── .cursor-plugin/                      ← GENERATED — Cursor marketplace catalog
│   └── marketplace.json
├── plugins/                             ← SOURCE — author plugins here
│   └── <plugin-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json              ← Claude Code manifest (authored)
│       ├── .cursor-plugin/
│       │   └── plugin.json              ← Cursor marketplace manifest (authored)
│       ├── assets/
│       │   └── logo.svg                 ← symlink to ../../../logo.svg (auto by build.sh)
│       ├── README.md                    ← Plugin-level install guide (authored)
│       ├── skills/
│       │   └── <skill-name>/
│       │       ├── SKILL.md             ← Source: frontmatter + instructions
│       │       └── references/          ← Deep-dive reference docs (loaded on demand)
│       ├── hooks/                       ← optional — hook definitions
│       └── rules/                       ← optional — cursor rules (.mdc files)
├── claude-config/                       ← Claude Code config (symlinked into ~/.claude/)
│   ├── settings.json
│   ├── install.sh
│   └── statusline/
├── scripts/
│   ├── build.sh                         ← Regenerate marketplace catalogs
│   └── validate.sh                      ← Lint manifests, skills, references, catalogs
└── .github/workflows/
    └── build.yml                        ← CI: build + validate + auto-commit catalogs
```

---

## Adding a New Plugin

### 1. Scaffold the plugin directory

```bash
PLUGIN_NAME="my-plugin"
mkdir -p "plugins/${PLUGIN_NAME}/{.claude-plugin,.cursor-plugin,assets,skills/my-skill/references}"
```

### 2. Author the plugin manifests

**`plugins/<plugin-name>/.claude-plugin/plugin.json`** (Claude Code):
```json
{
  "name": "my-plugin",
  "description": "Short description of what this plugin provides.",
  "author": { "name": "zarcen" },
  "homepage": "https://github.com/zarcen/ai-persona/tree/main/plugins/my-plugin"
}
```

**`plugins/<plugin-name>/.cursor-plugin/plugin.json`** (Cursor marketplace):
```json
{
  "name": "my-plugin",
  "displayName": "My Plugin",
  "version": "1.0.0",
  "description": "Short description of what this plugin provides.",
  "author": { "name": "zarcen" },
  "license": "MIT",
  "keywords": ["tag1", "tag2"],
  "logo": "assets/logo.svg"
}
```

### 3. Write `plugins/<plugin-name>/skills/<skill-name>/SKILL.md`

Required frontmatter fields: `name`, `description`.

```yaml
---
name: my-skill
description: >
  One paragraph that tells the agent WHEN to activate this skill.
  Be specific about trigger keywords, file types, and use cases.
parameters:
  some_param: "default_value"
globs:
  - "**/*.py"
---

# My Skill

You are an expert in <domain>. Follow these guidelines when ...

## Reference Files

- `references/topic-a.md` — description
```

**SKILL.md conventions:**
- `name` — lowercase kebab-case, matches directory name
- `description` — YAML folded scalar (`>`), used as agent trigger text
- Write in second person ("You are an expert...", "Always use...", "Never do...")
- Include concrete code examples
- End with a "Reference Files" section if you have references

### 4. Write reference docs (optional)

Place deep-dive material in `plugins/<plugin-name>/skills/<skill-name>/references/*.md`.
Keep each file under ~300 lines. Split large topics into multiple files.

### 5. Build

```bash
./scripts/build.sh my-plugin
```

This:
- Creates `assets/logo.svg` symlink if missing
- Regenerates `.claude-plugin/marketplace.json` and `.cursor-plugin/marketplace.json`

### 6. Validate

```bash
./scripts/validate.sh my-plugin
```

All checks must pass: manifests present and valid JSON, required fields, reference links valid.

### 7. Write `plugins/<plugin-name>/README.md`

Every plugin must have a README at the plugin root. Follow this template exactly:

```markdown
# <Plugin Display Name> Plugin

One-sentence description of what the plugin covers.

## Skills

| Skill | Description |
|-------|-------------|
| [<skill-name>](skills/<skill-name>/) | One-line description |

---

## Installation

### Claude Code (Plugin — recommended)

​```bash
claude plugin marketplace add zarcen/ai-persona
claude plugin install <plugin-name>@ai-persona
​```

### Claude Code (manual)

​```bash
# Download a skill folder and place it under .claude/skills/
gh repo clone zarcen/ai-persona /tmp/ai-persona && cp -r /tmp/ai-persona/plugins/<plugin-name>/skills/<skill-name> .claude/skills/
​```

### Cursor (Marketplace Plugin — recommended)

Install via the Cursor Marketplace using the `.cursor-plugin/marketplace.json` in this repo.

### Cursor (manual)

​```bash
# Download a skill folder and place it under .cursor/skills/
gh repo clone zarcen/ai-persona /tmp/ai-persona && cp -r /tmp/ai-persona/plugins/<plugin-name>/skills/<skill-name> .cursor/skills/
​```

### Codex

​```bash
ln -s ~/.codex/ai-persona/plugins/<plugin-name>/skills ~/.agents/skills/<plugin-name>
​```

---

## File Structure

​```
<plugin-name>/
├── .claude-plugin/plugin.json       # Claude Code manifest
├── .cursor-plugin/plugin.json       # Cursor marketplace manifest
├── assets/logo.svg
└── skills/
    └── <skill-name>/
        ├── SKILL.md                 # Main skill (frontmatter + instructions)
        └── references/              # Deep-dive reference docs
            └── *.md
​```
```

**Rules:**
- Manual install uses `gh repo clone` + `cp -r` — never enumerate individual files
- One README per plugin, no README inside individual skill directories
- Keep the section order: Skills table → Installation → File Structure

### 8. Update root README.md

Add a row to the plugins table in the root `README.md`. The table has only two columns — Plugin and Description — do **not** list individual skills there. Skills are listed in the plugin's own README.

### 9. Commit

```bash
git add plugins/my-plugin .claude-plugin/marketplace.json .cursor-plugin/marketplace.json README.md
git commit -m "feat: add my-plugin"
```

---

## Bumping a Plugin Version

Both plugin manifests must declare the same `version` — `validate.sh` fails if they differ.

### 1. Edit version in both manifests

```bash
# plugins/<name>/.claude-plugin/plugin.json
# plugins/<name>/.cursor-plugin/plugin.json
# Set "version" to the new value in both files.
```

### 2. Rebuild and validate

```bash
./scripts/build.sh <name>     # regenerates marketplace catalogs with the new version
./scripts/validate.sh <name>  # confirms versions are consistent and catalogs are correct
```

### 3. Commit

```bash
git add plugins/<name>/.claude-plugin/plugin.json \
        plugins/<name>/.cursor-plugin/plugin.json \
        .claude-plugin/marketplace.json \
        .cursor-plugin/marketplace.json
git commit -m "chore(<name>): bump version to x.y.z"
```

> CI rebuilds and re-commits the marketplace catalogs automatically on push to `main`,
> so steps 2–3 for the catalog files are handled for you if you push directly.

---

## Build System

### `scripts/build.sh`

- Iterates `plugins/*/` and reads authored `.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json`
- Ensures `assets/logo.svg` symlink exists in each plugin
- Regenerates `.claude-plugin/marketplace.json` and `.cursor-plugin/marketplace.json`

Plugin manifests (`plugin.json`) are **authored directly** — they are never auto-generated.

### `scripts/validate.sh`

Checks per plugin:
- `.claude-plugin/plugin.json` — exists, valid JSON
- `.cursor-plugin/plugin.json` — exists, valid JSON, required fields (`name`, `displayName`, `description`)
- `assets/logo.svg` symlink — exists and resolves
- At least one `skills/*/SKILL.md` with required frontmatter (`name`, `description`)
- All `references/` cross-links in SKILL.md resolve to real files

Checks globally:
- `.claude-plugin/marketplace.json` — valid JSON, entry for every plugin
- `.cursor-plugin/marketplace.json` — valid JSON, entry for every plugin

### CI (`.github/workflows/build.yml`)

On every push/PR to `main`:
1. Builds all plugins (regenerates marketplace catalogs)
2. Validates all plugins
3. Lints skills with `skill-validator` (non-blocking)
4. On main branch pushes: auto-commits updated marketplace catalogs with `[skip ci]`

---

## Conventions

- **Plugin names**: lowercase kebab-case (e.g. `k8s`, `react`, `python-data`)
- **Skill names**: lowercase kebab-case (e.g. `k8s-operator`, `react-testing`)
- **One skill per directory**: never nest skills
- **Plugin manifests are authored**: edit `.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json` directly
- **Commit marketplace catalogs**: always commit `.claude-plugin/marketplace.json` and `.cursor-plugin/marketplace.json`
- **No secrets**: never put API keys, tokens, or credentials in any file
- **Test locally**: always run `validate.sh` before pushing

---

## Quick Reference

| Task | Command |
|------|---------|
| Build all plugins | `./scripts/build.sh` |
| Build one plugin | `./scripts/build.sh <name>` |
| Validate all | `./scripts/validate.sh` |
| Validate one | `./scripts/validate.sh <name>` |
| Install (Claude Code plugin) | `claude plugin marketplace add zarcen/ai-persona` then `claude plugin install <plugin>@ai-persona` |
| Install (Cursor marketplace) | Install via Cursor Marketplace using `.cursor-plugin/marketplace.json` |
| Install (Codex) | `ln -s ~/.codex/ai-persona/plugins/<name>/skills ~/.agents/skills/<name>` |
