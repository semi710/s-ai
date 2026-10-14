# Architecture

s-ai is a nix flake module that closes over its own inputs (agent versions,
skill sources) and exposes a single `homeModules.s-ai`. Consumers import it,
set providers/plugins/etc., and s-ai renders the canonical layer into each
agent's native format.

## Repo layout

```
flake.nix                # flake-parts: homeModules.s-ai, packages (omp/pi/opencode), test-home, checks
modules/default.nix      # canonical options: agents, plugins, mcp, providers, theme, prompts
modules/agents/*.nix     # per-agent translation (omp/pi/opencode)
modules/lib/skills.nix   # plugins -> per-agent home.file skill mappings
modules/lib/prompts.nix  # numbered markdown -> combined system prompt
modules/theme.nix        # base16 palette -> omp theme (66 slots)
plugins/core/skills/     # the shared skill set
prompts/                 # numbered system-prompt files (01-git, ...)
testhost/                # scratch consumer for testing changes
```

## How the canonical layer becomes per-harness files

A plugin, MCP server, provider, palette, or prompt is declared once in the
canonical options. Each agent module (`modules/agents/<name>.nix`) reads the
canonical set and emits the harness's native config:

| Canonical | opencode | omp | pi |
|---|---|---|---|
| skills | `~/.config/opencode/skills/` | `~/.omp/agent/skills/` | `~/.pi/agent/skills/` |
| MCP | `programs.opencode` MCP integration | `~/.omp/agent/mcp.json` | `~/.pi/agent/mcp.json` |
| providers | `provider` attrset | `models.yml` | `models.json` |
| prompt | `AGENTS.md` | `AGENTS.md` | `AGENTS.md` |
| theme | — (opencode themes its own TUI) | derived `s-ai-dark/light` | `theme = "dark"` |

### Skill routing

Each plugin owns a `skills.dir`. `skills.agents` decides which agents get
the skills symlinked. A plugin loaded through an agent's native mechanism
(ponytail via opencode's `.mjs` / pi's package system) *excludes* that agent
so skills are not double-registered. `skills.copyAllFiles` marks authored
skills: every file ships (checklists, templates) and SKILL.md front matter
is validated at eval time; vendored inputs ship SKILL.md only and get the
duplicate-name check, so upstream breakage cannot wedge eval.

### MCP schema translation

Each harness's MCP config schema differs:

- **opencode** accepts a `stdio` server with `command`/`args`/`env`, or a
  remote server with `type`/`url`/`headers`.
- **omp** is strict (`additionalProperties: false`): stdio takes
  `command`/`args`/`env`, http takes `type`/`url`/`headers`. Pi-only keys
  (lifecycle, directTools, autoApprove) are stripped and `{env:VAR}` values
  become env-var names.
- **pi** validates: url servers take `type` = `"http"`/`"streamable-http"` or
  no `type` at all; command servers take `"stdio"` or none. The canonical
  `type = "remote"` is translated away to `{ url, headers? }`.

Host-level `programs.mcp.servers` additions merge into the canonical set and
land in every agent, so a workstation-level `bitbucket` server reaches all
three.

## Declarative / imperative posture

- Read-only data (skills, mcp.json, models, themes, AGENTS.md) renders as
  store symlinks - agents read them, they cannot rot.
- Agent-editable settings (**omp**'s `config.yml`, **OMO**'s `omo.jsonc`)
  render as **writable copies** via `home.activation`. The agents rewrite
  them at runtime; the next switch re-asserts the declared values.

## Secrets boundary

Providers accept only **env-var names** (`apiKeyEnv`), never values. The
store contains no secrets; the consumer exports values via sops or
session env.

## Sandboxing / isolation

- Each binary lives in its own store path; versions never clash with system
  packages.
- Renders are read-only symlinks; agent runtime state stays in its own home
  dir (`~/.omp`, `~/.pi`, `~/.config/opencode`).
- Agents are NOT OS-sandboxed by design - a coding agent needs repo write,
  git, network, and a TTY. Guardrails are the agents' own permission prompts
  (tuned via `extraSettings`) and per-invocation worktrees/VMs.

## Systems

The flake lists `x86_64-linux`, `aarch64-linux`, `aarch64-darwin` manually
rather than `nix-systems/default`: that includes `x86_64-darwin`, which
llm-agents publishes no packages for. This is the actual support
intersection of the agent inputs.