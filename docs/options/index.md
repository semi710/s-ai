# Options

s-ai's full option surface, grouped by concern. Everything is consumer
config under `s-ai.*`; secrets never enter the store (only env-var names).

## Agents

| Option | Default | Description |
|---|---|---|
| `s-ai.agents.opencode.enable` | `true` | opencode |
| `s-ai.agents.opencode.omo` | `true` | oh-my-openagent |
| `s-ai.agents.opencode.extraSettings` | `{}` | deep-merges last into opencode settings |
| `s-ai.agents.opencode.extraOmoConfig` | `{}` | deep-merges last into `~/.omo/omo.jsonc` |
| `s-ai.agents.omp.enable` | `true` | omp (oh-my-pi) |
| `s-ai.agents.omp.prewalk` | `true` | strong model plans, smol role implements |
| `s-ai.agents.omp.advisor` | `true` | second-opinion reviewer on stop |
| `s-ai.agents.omp.advisorModel` | `null` | advisor role model id |
| `s-ai.agents.omp.smolModel` | `null` | smol role model id |
| `s-ai.agents.omp.memory` | `true` | local SQLite per-project memory |
| `s-ai.agents.omp.extraSettings` | `{}` | deep-merges last into omp settings |
| `s-ai.agents.pi.enable` | `true` | pi |
| `s-ai.agents.pi.vimMotions` | `true` | vim-motions-pi plugin |
| `s-ai.agents.pi.clipboardCommand` | `null` | OSC 52 command for vim-motions |
| `s-ai.agents.pi.extraSettings` | `{}` | deep-merges last into pi settings |

## Plugins

A plugin is a skills directory plus per-harness loading hooks. `skills.agents`
decides which agents get the skills symlinked; plugins loaded through an
agent's native mechanism exclude that agent so skills are not
double-registered.

| Builtin | Default | What |
|---|---|---|
| `core` | enabled | the shared skill set (`plugins/core/skills`) |
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
  opencodePlugin = ./plugin.mjs;        # opencode loads this instead of symlinking
  piPackage = "git:github.com/org/repo";# pi loads via its package system
};
```

`copyAllFiles` gates eval-time validation: authored skills must have valid
SKILL.md front matter (name + description); vendored inputs only get the
duplicate-name check, so upstream breakage cannot wedge eval.

## MCP

`s-ai.mcp.servers` is the canonical set (git, fetch, everything, playwright,
deepwiki, nixos, context7, grep_app, codegraph by default). Consumer and
host-level `programs.mcp.servers` additions merge in and land in every
agent. Work-specific tiers belong to the consumer.

```nix
s-ai.mcp.servers.my-work-tool = {
  command = "my-work-tool";
  env.MY_WORK_TOKEN = "{env:MY_WORK_TOKEN}";
};
```

The canonical `type = "remote"` is translated per harness; see
[architecture](../architecture.md#mcp-schema-translation).

## Providers

`providers` are openai-compatible grids rendered into all three agents.
Secrets are env-var names only (`apiKeyEnv`); the consumer exports values.

```nix
s-ai.providers.my-grid = {
  baseUrl = "https://grid.example";
  apiKeyEnv = "MY_API_KEY";
  timeout = 600000;
  models = [
    # a bare id (omp falls back to its 128k context default)
    "model-default"
    # or an attrset pinning the model's real window so omp's context
    # meter and compaction match what the grid actually serves
    { id = "model-large"; contextWindow = 400000; maxTokens = 32000; }
  ];
  defaultModel = "model-default";
};
s-ai.defaultProvider = "my-grid";
```

`contextWindow`/`maxTokens` flow into omp's `models.yml`, pi's `models.json`,
and opencode's model blocks. Without them omp shows 128k - often wrong for
the served model; this repository's examples always set them from the grid's
`/v1/models` (`max_input_tokens`/`max_output_tokens`).

## Prompts

Every agent's `AGENTS.md` is the sorted concatenation of numbered markdown
files. s-ai ships the builtin set (01-git, 02-before-you-code,
03-code-comments, 04-docs, 05-nix); add your own rules or override builtin
files by name.

```nix
s-ai.prompts.dirs = [ ./my-prompts ];     # 06-docker.md, 90-team-rules.md, ...
# same-named files override builtins: your 03-code-comments.md replaces ours
s-ai.prompts.builtin = false;             # ship only your own set
```

## Theme

`s-ai.theme.palette` drives the derived omp themes (`s-ai-dark`/`s-ai-light`)
which map every one of omp's 66 color slots onto the palette. Pass
`config.lib.stylix.colors` as-is (extra keys are ignored) or a plain base16
set (hex, no `#`).

```nix
s-ai.theme.palette = config.lib.stylix.colors;
```