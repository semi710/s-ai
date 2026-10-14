# s-ai

Coding agents (opencode, oh-my-pi, pi) sharing one canonical layer:
skills, prompts, MCP servers, providers, themes. Each agent module
translates the canonical options into its harness's native format - define
once, land in every agent.

## Options

- **Agents**: `s-ai.agents.{opencode,omp,pi}.enable` + per-agent toggles + `extraSettings`
- **Skills**: `s-ai.plugins.<name>` - builtin set (`core`, `ponytail`, `claude-code`, `workmux`) + your own
- **MCP**: `s-ai.mcp.servers` canonical set, merged with host-level `programs.mcp.servers`
- **Providers**: `s-ai.providers.<name>` (openai-compatible grids) + `s-ai.defaultProvider`
- **Prompts**: `s-ai.prompts.{builtin, dirs}` - numbered markdown → combined AGENTS.md
- **Theme**: `s-ai.theme.palette` - raw `config.lib.stylix.colors` or plain base16
- **Escapes**: `extraSettings` / `extraOmoConfig` deep-merge last on every agent

## Declarative / imperative posture

Read-only data (skills, mcp.json, models, themes, AGENTS.md) renders as
store symlinks - agents read them, they cannot rot. Agent-editable settings
(omp's `config.yml`, OMO's `omo.jsonc`) render as writable copies: runtime
changes work and survive until the next switch, which re-asserts the
declared values.