# Agents

s-ai configures four coding agents from a shared canonical layer.

| Agent | Home dir | Package source |
|---|---|---|
| **opencode** | `~/.config/opencode` | `opencode-vim` fork (`@ai-sdk/openai-compatible`) |
| **omp** (oh-my-pi) | `~/.omp/agent` | oh-my-pi flake |
| **pi** | `~/.pi/agent` | `llm-agents.pi` |
| **claude** (Claude Code) | `~/.claude` | nixpkgs `claude-code` (**unfree**) |

opencode/omp/pi are enabled by default. claude is opt-in: it pulls the
unfree `claude-code` package, so allow it in `nixpkgs.config` or substitute
`s-ai.agents.claude.package`. Disable per consumer with
`s-ai.agents.<name>.enable = false`.

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
- vim-motions-pi plugin (optional, upstream pin) for `jk` escape + OSC 52 yank
- pi-copy-mode + pi-xsettings (optional) for vim-style transcript selection,
  copy, comments and reactions (`ctrl+x`, then `v`/`y`)
- scroll keys outside copy mode (`ctrl+d`/`ctrl+u` half page, `ctrl+g` bottom)
  are pi-native `keybindings.json` entries, not plugin code; viewport-level, so
  they work in insert mode too and shadow pi's `ctrl+d` quit
- `~/.pi/agent/keybindings.json` rendered declaratively (store symlink)
- mcp.json rendered with pi's `lifecycle = "keep-alive"` + `directTools = true` keys, and the canonical `type = "remote"` translated to `{ url, headers? }` (pi rejects `type = "remote"`)

Options:

| Option | Default | Description |
|---|---|---|
| `s-ai.agents.pi.enable` | `true` | pi |
| `s-ai.agents.pi.vimMotions` | `true` | vim-motions-pi plugin (upstream) |
| `s-ai.agents.pi.copyMode` | `false` | pi-copy-mode + pi-xsettings (transcript copy, annotations) |
| `s-ai.agents.pi.extraPackages` | `[]` | extra pi package specs (npm:, git:, paths) |
| `s-ai.agents.pi.clipboardCommand` | `null` | OSC 52 command (e.g. `pkgs.copy`) |
| `s-ai.agents.pi.extraSettings` | `{}` | deep-merged last into pi settings |

## claude (Claude Code)

- speaks the **Anthropic Messages API** against a single endpoint: the
  default provider drives `ANTHROPIC_BASE_URL`, `model` and `apiKeyHelper`
  (the key stays out of the store). The provider must declare
  `protocols = [ ... "anthropic" ]`
- `~/.claude/settings.json` rendered declaratively (store symlink)
- `~/.claude/CLAUDE.md` gets the same combined prompts as every agent's
  AGENTS.md
- user-scope MCP is **merged** into `~/.claude.json` (claude's live state
  file - `settings.json` cannot carry MCP, and a symlink would freeze the
  state)
- skills symlinked to `~/.claude/skills` (the vendored frontend-design
  skill returns home)

Options:

| Option | Default | Description |
|---|---|---|
| `s-ai.agents.claude.enable` | `false` | claude (opt-in: unfree package) |
| `s-ai.agents.claude.package` | `pkgs.claude-code` | substitute your own build |
| `s-ai.agents.claude.extraSettings` | `{}` | deep-merged last into `~/.claude/settings.json` |

All agents share the same canonical prompts (`AGENTS.md`/`CLAUDE.md`),
skills (per-plugin routing), MCP servers, providers, and (for omp) theme.

## Pi Durable (watchlist - not integrated)

[Pi Durable](https://earendil.com/posts/pi-durable/) (`@earendil-works/pi-durable`)
is an experimental framework for building durable agent apps: checkpointed tasks
that survive crashes and replay only when `replay: "safe"`, forking with shared
transcript, an ownership tree for foreground/background work, background
compaction, and multi-client steering. It is **not an agent and not a config
layer** - there is nothing for s-ai to render; adopting it means building and
maintaining a TypeScript app.

Not integrated on purpose: the API is explicitly unstable, storage is
single-writer (one process owns it, clients attach), it is TypeScript-only, and
the announced first real apps (Slack bot, GitHub triage bot) had not shipped at
time of writing.

TODO(pi-durable): reassess when either of these lands -
1. the promised Slack/GitHub triage bots ship (signals API stabilization), or
2. a concrete workload appears that must survive process death mid-tool-call
   (scheduled job, chat-surface bot, unattended long run).

If (2) happens, spike first: run `packages/coding-agent/src/experimental/vacation/main.ts`
from a pi `v1.0.0` checkout, kill the process mid-search, restart, confirm only
unsafe tasks rerun. Keep any resulting app in its own repo + nix derivation
(bun app), never inside this module.