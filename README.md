# ai-persona

A marketplace of portable agent plugins — skills, hooks, and rules for AI coding agents, version-controlled and shareable across tools and machines.

---

## Plugins

| Plugin | Skills | Description |
|--------|--------|-------------|
| [k8s](plugins/k8s/) | [k8s-operator](plugins/k8s/skills/k8s-operator/) | Kubernetes development — operators, CRDs, controllers, client-go, envtest |

> See each plugin's README for full installation instructions.

---

## Install

### Claude Code (Plugin — recommended)

```bash
claude plugin marketplace add zarcen/ai-persona
claude plugin install <plugin-name>@ai-persona
```

### Claude Code (manual)

```bash
gh repo clone zarcen/ai-persona /tmp/ai-persona
cp -r /tmp/ai-persona/plugins/<plugin-name>/skills/<skill-name> .claude/skills/
```

### Cursor (Marketplace Plugin — recommended)

Install via the Cursor Marketplace using `.cursor-plugin/marketplace.json` in this repo.

### Cursor (manual)

```bash
gh repo clone zarcen/ai-persona /tmp/ai-persona
cp -r /tmp/ai-persona/plugins/<plugin-name>/skills/<skill-name> .cursor/skills/
```

### Codex

```bash
git clone https://github.com/zarcen/ai-persona.git ~/.codex/ai-persona
mkdir -p ~/.agents/skills
ln -s ~/.codex/ai-persona/plugins/<plugin-name>/skills ~/.agents/skills/<plugin-name>
```

---

## Tool Config

Per-tool config files symlinked from this repo — `git pull` on any machine instantly applies changes.

```bash
git clone https://github.com/zarcen/ai-persona.git
sh ai-persona/claude-config/install.sh   # Claude Code statusline
```

| Tool | Config | Description |
|------|--------|-------------|
| Claude Code | [statusline](claude-config/statusline/) | Custom statusline: working directory, model name, context window usage |

---

## Repo Structure

```
ai-persona/
├── .claude-plugin/              # GENERATED — Claude Code marketplace catalog
│   └── marketplace.json
├── .cursor-plugin/              # GENERATED — Cursor marketplace catalog
│   └── marketplace.json
├── plugins/                     # SOURCE — author plugins here
│   └── <plugin-name>/
│       ├── .claude-plugin/plugin.json   # Claude Code manifest (authored)
│       ├── .cursor-plugin/plugin.json   # Cursor marketplace manifest (authored)
│       ├── assets/logo.svg              # symlink to repo root logo.svg
│       ├── README.md                    # Plugin install guide
│       ├── skills/
│       │   └── <skill-name>/
│       │       ├── SKILL.md             # frontmatter + instructions
│       │       └── references/          # deep-dive docs (loaded on demand)
│       ├── hooks/                       # optional
│       └── rules/                       # optional
├── claude-config/               # Claude Code config (symlinked into ~/.claude/)
├── scripts/
│   ├── build.sh                 # Regenerate marketplace catalogs
│   └── validate.sh              # Lint manifests, skills, references
└── .github/workflows/
    └── build.yml                # Auto-rebuild on push to main
```

---

## Contributing

See [AGENTS.md](AGENTS.md) for the full contributor guide — plugin/skill conventions, manifest formats, and the step-by-step workflow for adding new plugins.

```bash
./scripts/build.sh        # regenerate marketplace catalogs
./scripts/validate.sh     # lint everything
```
