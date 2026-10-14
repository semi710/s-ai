# Agents

s-ai configures three coding agents from a shared canonical layer.

| Agent | Home dir | Package source |
|---|---|---|
| **opencode** | `~/.config/opencode` | `opencode-vim` fork (`@ai-sdk/openai-compatible`) |
| **omp** (oh-my-pi) | `~/.omp/agent` | oh-my-pi flake |
| **pi** | `~/.pi/agent` | `llm-agents.pi` |

Each enabled by default; disable per consumer with `s-ai.agents.<name>.enable = false`.

## opencode

- Runtime + TUI via the upstream opencode home-manager module
- **OMO** (oh-my-openagent) plugin: Sisyphus agent system, team mode, subagents. Writes `~/.omo/omo.jsonc` as a **writable copy** (not a store symlink) so OMO's migration system and runtime `/settings` edits work.
- `plugin` list from enabled plugins + OMO
- Providers rendered as opencode `provider` attrsets with `modalities`

Options:

| Option | Default | Description |
|---|---|---|
| `s-ai.agents.opencode.enable` | `true` | opencode |
| `s-ai.agents.opencode.omo` | `true` | oh-my-openagent |
| `s-ai.agents.opencode.extraSettings` | `{}` | deep-merged last into `programs.opencode.settings` |
| `s-ai.agents.opencode.extraOmoConfig` | `{}` | deep-merged last into `~/.omo/omo.jsonc` |

## omp (oh-my-pi)

- `modelRoles`: default from `s-ai.defaultProvider`/`defaultModel`; `advisor`/`smol` unarmed (null) unless you set `advisorModel`/`smolModel`
- memory (mnemopi), advisor, prewalk toggles
- vim-mode TUI, pi-style composer, nerd glyphs
- `config.yml` written as a **writable copy** by the upstream omp home-manager module (runtime `/settings` edits persist until the next switch)
- themes: `s-ai-dark`/`s-ai-light` from your palette; `keybindings.yml` from the `keybindings` option

Options:

| Option | Default | Description |
|---|---|---|
| `s-ai.agents.omp.enable` | `true` | omp |
| `s-ai.agents.omp.prewalk` | `true` | strong model plans, smol role implements |
| `s-ai.agents.omp.advisor` | `true` | second-opinion reviewer on stop |
| `s-ai.agents.omp.advisorModel` | `null` | advisor role model id (unarmed when null) |
| `s-ai.agents.omp.smolModel` | `null` | smol role model id - prewalk exec, commits, background (unarmed when null) |
| `s-ai.agents.omp.memory` | `true` | local SQLite per-project memory (mnemopi) |
| `s-ai.agents.omp.extraSettings` | `{}` | deep-merged last into `programs.omp.settings` |

## pi

- `programs.pi-coding-agent` upstream module
- vim-motions-pi plugin (optional) for `jk` escape + OSC 52 yank
- mcp.json rendered with pi's `lifecycle = "keep-alive"` + `directTools = true` keys, and the canonical `type = "remote"` translated to `{ url, headers? }` (pi rejects `type = "remote"`)

Options:

| Option | Default | Description |
|---|---|---|
| `s-ai.agents.pi.enable` | `true` | pi |
| `s-ai.agents.pi.vimMotions` | `true` | vim-motions-pi plugin |
| `s-ai.agents.pi.clipboardCommand` | `null` | OSC 52 command (e.g. `pkgs.copy`) |
| `s-ai.agents.pi.extraSettings` | `{}` | deep-merged last into pi settings |

All agents share the same canonical prompts (`AGENTS.md`), skills
(per-plugin routing), MCP servers, providers, and (for omp) theme.