# Decisions

Architecture decisions and their reasons, newest first.

## claude: MCP merges into `~/.claude.json`, settings.json symlinks

`settings.json` cannot carry MCP (no `mcpServers` in its schema); user-scope
servers live in `~/.claude.json`, which is also claude's live state file
(projects, onboarding). A store symlink would freeze its writes and a
writable copy would clobber the state, so activation merges only our
`mcpServers` key via jq. `settings.json` is read-only declarative config
and symlinks fine.

## claude agent: opt-in unfree, single endpoint from the default provider

Claude Code speaks the Anthropic Messages API against one base URL - there
is no provider grid in its config. The default provider renders as
`ANTHROPIC_BASE_URL`/`model`/`apiKeyHelper` and must declare protocol
`anthropic`. `ANTHROPIC_SMALL_FAST_MODEL` follows the default model: grid
ids are not claude aliases, so the built-in haiku fallback would 404. The
nixpkgs `claude-code` package is unfree, so `agents.claude.enable` defaults
to false and this flake allows exactly `claude-code` in its own per-system
pkgs (test-home, `.#claude-code`).

## Provider models are str-or-attrset with real context windows

omp defaults any openai-compatible model to a 128k context - usually a lie.
Provider `models` entries accept `{ id, contextWindow, maxTokens }` attrsets
rendered into pi/omp/opencode (claude knows its models' windows). The grid's `/v1/models`
(`max_input_tokens`/`max_output_tokens`) is the source of truth; bare
strings still work when you do not care.

## Work tier belongs to the consumer, not s-ai

s-ai ships zero work-specific config. ndots defines the juspay provider,
`ndots.ai.mcp.workServers` (github, newton-hs-prod), and host enablement.
s-ai's testhost uses a dummy `example` provider so the module builds without
any private data.

## `~/.omo/omo.jsonc` is a writable activation copy, not a home.file symlink

OMO's migration engine resolves symlinks and rejects `/nix/store/...` paths
("Migration target is not an omo config path"). A `home.activation` +
`install -m 600` writable copy at the canonical path, with all six
`_migrations` ids pre-marked, boots clean.

## pi mcp.json: translate `type = "remote"` away

pi validates `type` strictly (http/streamable-http/stdio/absent). The
canonical remote form is rendered as `{ url, headers? }` for pi only; omp
keeps `type` because its schema requires it.

## Secrets are env-var names, never values

Providers take `apiKeyEnv`. The nix store is world-readable on multi-user
systems; values come from sops/session env at runtime.

## Read-only symlinks vs writable copies

Static data (skills, mcp.json, models, themes, AGENTS.md) is
store-symlinked - agents read, they cannot rot. Agent-editable state (omp
`config.yml`, OMO `omo.jsonc`) is a writable copy re-asserted on each
switch: runtime edits work, declarative values win on switch.

## Manual `systems` list

`nix-systems/default` includes `x86_64-darwin`, which llm-agents publishes
no packages for. The three-system list is the actual support intersection
of the agent inputs.

## Local development consumption: `path:` input + lock refresh

ndots consumes s-ai via `path:/home/nikhil.singh/work/s-ai`. Relative
`path:../s-ai` does not work: path inputs resolve against the store copy of
the consuming flake. After editing s-ai, run
`nix flake lock --update-input s-ai` in the consumer.
