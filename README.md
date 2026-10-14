# s-ai

Coding agents (opencode, oh-my-pi, pi) with one shared canonical layer:
skills, prompts, MCP servers, providers, themes. Each agent module
translates the canonical options into its harness's native format, so a
plugin, provider, or MCP server is defined once and lands everywhere.

```
nix run github:semi710/s-ai#omp        # try an agent binary
nix build .#test-home                   # test host build
```

## Use

```nix
# flake.nix
inputs.s-ai.url = "github:semi710/s-ai";

# home-manager config
imports = [ inputs.s-ai.homeModules.s-ai ];
```

The module closes over its own inputs (agent versions, skill sources), so
consumers need no specialArgs. Providers are consumer config; secrets never
enter the store - only env-var names are rendered.

```nix
s-ai.providers.example = {
  baseUrl = "https://your-openai-compatible-grid.example";
  apiKeyEnv = "EXAMPLE_API_KEY";    # export the value yourself (sops, etc.)
  models = [ "model-large" "model-fast" ];
  defaultModel = "model-large";
};
s-ai.defaultProvider = "example";
s-ai.theme.palette = config.lib.stylix.colors;  # optional: raw stylix colors work as-is
```

## Options

### Agents

| Option | Default | Description |
|---|---|---|
| `s-ai.agents.opencode.enable` | `true` | opencode (writes `~/.config/opencode`) |
| `s-ai.agents.omp.enable` | `true` | oh-my-pi (writes `~/.omp/agent`) |
| `s-ai.agents.pi.enable` | `true` | pi (writes `~/.pi/agent`) |
| `s-ai.agents.omp.prewalk` | `true` | strong model plans, smol role implements (cost/quality dial) |
| `s-ai.agents.omp.advisor` | `true` | second-opinion reviewer on stop |
| `s-ai.agents.omp.advisorModel` | `null` | model id for the advisor role (unarmed when null) |
| `s-ai.agents.omp.smolModel` | `null` | model id for the smol role - prewalk execution, commits, background tasks (unarmed when null) |
| `s-ai.agents.omp.memory` | `true` | local SQLite per-project memory (mnemopi) |
| `s-ai.agents.omp.extraSettings` | `{}` | deep-merged last into `programs.omp.settings` |
| `s-ai.agents.pi.vimMotions` | `true` | vim-motions-pi plugin (jk escape, OSC 52 yank) |
| `s-ai.agents.pi.clipboardCommand` | `null` | OSC 52 command for vim-motions (your `copy` tool) |
| `s-ai.agents.pi.extraSettings` | `{}` | deep-merged last into pi settings |
| `s-ai.agents.opencode.omo` | `true` | oh-my-openagent (Sisyphus agent system) |
| `s-ai.agents.opencode.extraSettings` | `{}` | deep-merged last into opencode settings |
| `s-ai.agents.opencode.extraOmoConfig` | `{}` | deep-merged last into `~/.omo/omo.jsonc` |

### Plugins

A plugin is a skills directory plus loading hooks. `skills.agents` decides
which agents get the skills symlinked; plugins loaded through an agent's own
mechanism (ponytail via opencode's `.mjs` / pi's package system) exclude that
agent so skills are not double-registered.

| Builtin | Default | What |
|---|---|---|
| `core` | enabled | the shared skill set (`plugins/core/skills`) - required |
| `ponytail` | enabled | lazy-dev skill; opencode plugin + pi package + omp symlink |
| `claude-code` | enabled | frontend-design skill, vendored from claude-code |
| `workmux` | disabled | worktree/tmux workflow skills |

```nix
s-ai.plugins.workmux.enable = true;

# your own plugin
s-ai.plugins.my-tools = {
  enable = true;
  skills.dir = ./my-skills;             # <name>/SKILL.md dirs
  skills.agents = [ "omp" "pi" ];       # default: all three
  skills.copyAllFiles = true;           # ship every file + validate front matter
  env.MY_TOOL_MODE = "1";               # exported while enabled
};
```

`copyAllFiles` also gates eval-time validation: authored skills must have
valid SKILL.md front matter (name + description); vendored inputs only get
the duplicate-name check, so upstream breakage cannot wedge eval.

### MCP

`s-ai.mcp.servers` is the canonical set (git, fetch, everything, playwright,
deepwiki, nixos, context7, grep_app, codegraph by default); consumer and
host-level `programs.mcp.servers` additions merge in and land in every
agent. Work-specific tiers belong to the consumer:

```nix
s-ai.mcp.servers.my-work-tool = {
  command = "my-work-tool";
  env.MY_WORK_TOKEN = "{env:MY_WORK_TOKEN}";
};
```

### Providers

`s-ai.providers.<name>` (openai-compatible grids): `baseUrl`, `apiKeyEnv`,
`timeout`, `models`, `defaultModel`. Rendered into all three agents.
`s-ai.defaultProvider` picks the grid the agents default to.

### Prompts

Every agent's `AGENTS.md` is the sorted concatenation of numbered markdown
files. s-ai ships the builtin set (01-git, 02-before-you-code,
03-code-comments, 04-docs, 05-nix); add your own rules or override builtin
files by name:

```nix
s-ai.prompts.dirs = [ ./my-prompts ];   # 06-docker.md, 90-team-rules.md, ...
# same-named files override builtins: your 03-code-comments.md replaces ours
s-ai.prompts.builtin = false;           # ship only your own set
```

## Declarative / imperative posture

Read-only data (skills, mcp.json, models, themes, AGENTS.md) renders as
store symlinks - agents read them, they cannot rot. Agent-editable settings
(omp's `config.yml`) render as a writable copy: runtime changes (e.g. omp's
`/settings`) work and survive until the next switch, which re-asserts the
declared values.

## Isolation stance

- Each binary lives in its own store path; versions never clash with system
  packages (nix paths, no global installs).
- Renders are read-only symlinks; agent runtime state stays in its own home
  dir (`~/.omp`, `~/.pi`, `~/.config/opencode`) - configs cannot corrupt.
- No secrets in the store: only env-var names; you export values via sops.
- Agents are NOT OS-sandboxed by design: a coding agent needs repo write,
  git, network, and a TTY. The guardrails that fit that reality are the
  agents' own permission prompts (tuned via `extraSettings`) and running
  risky work in worktrees/VMs per invocation.

## Layout

```
modules/default.nix      canonical options + builtin plugin/MCP defaults
modules/agents/*.nix     per-agent translation of the canonical layer
modules/lib/skills.nix   plugins -> per-agent home.file skill mappings
modules/lib/prompts.nix  numbered markdown -> combined system prompt
modules/theme.nix        base16 palette -> omp theme (66 slots)
plugins/core/skills/     the shared skill set
prompts/                 numbered system-prompt files (01-git, ...)
testhost/                scratch consumer for testing changes
```

Bump agents with `nix flake update <input>`. omp compiles from source on
first build (bun2nix); plan a binary cache before sharing widely.
