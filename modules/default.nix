# s-ai - coding agents with a shared canonical layer.
#
# Canonical options live here (plugins, MCP, providers, palette); each agent
# module (agents/*.nix) translates them into its harness's native format.
# Everything users need to toggle is an option; anything else is overridable
# through the per-agent `extraSettings` escape hatch, which deep-merges last.
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) getExe getExe';

  cfg = config.s-ai;

  enabledPlugins = lib.filterAttrs (_: p: p.enable) cfg.plugins;

  # universal MCP set - used in nearly every session
  universalServers = {
    git.command = getExe pkgs.mcp-server-git;
    fetch.command = getExe pkgs.mcp-server-fetch;
    sequential-thinking.command = getExe' pkgs.mcp-server-sequential-thinking "mcp-server-sequential-thinking";
    everything = {
      command = getExe pkgs.mcp-server-filesystem;
      args = [ "${config.home.homeDirectory}" ];
    };
    playwright.command = getExe pkgs.playwright-mcp;
    deepwiki = {
      type = "remote";
      url = "https://mcp.deepwiki.com/mcp";
      enabled = true;
    };
    # direct binary - `nix run github:utensils/mcp-nixos` re-evaluated the
    # flake on every agent boot (1-15s cold)
    nixos.command = getExe pkgs.mcp-nixos;
    # parity with the servers OMA injects into opencode, so every agent gets them
    context7 = {
      type = "remote";
      url = "https://mcp.context7.com/mcp";
    };
    grep_app = {
      type = "remote";
      url = "https://mcp.grep.app";
    };
    codegraph = {
      command = getExe pkgs.codegraph;
      # bare `codegraph` opens the interactive setup wizard and never answers
      # initialize, hanging the whole MCP startup for the 60s SDK timeout
      args = [
        "serve"
        "--mcp"
      ];
    };
  };
in
{
  options.s-ai = {
    agents.opencode.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "opencode agent (writes ~/.config/opencode)";
    };
    agents.omp.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "oh-my-pi agent (writes ~/.omp/agent)";
    };
    agents.pi.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "pi coding agent (writes ~/.pi/agent)";
    };

    # A plugin is a portable unit of agent configuration: a skills directory,
    # environment variables, and per-harness loading hooks. Users can define
    # their own by adding an attribute here.
    plugins = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "load this plugin into its target agents";
            };
            skills.dir = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "directory of <name>/SKILL.md skills";
            };
            skills.agents = lib.mkOption {
              type = lib.types.listOf (
                lib.types.enum [
                  "opencode"
                  "pi"
                  "omp"
                ]
              );
              default = [
                "opencode"
                "pi"
                "omp"
              ];
              description = "agents whose skills directory gets these skills symlinked";
            };
            # also gates front-matter validation: copyAllFiles marks authored
            # skills (validated); vendored inputs only get the duplicate check
            skills.copyAllFiles = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "symlink every file in each skill dir, not just SKILL.md";
            };
            # vendored skills that ship scripts and subdirectories (e.g.
            # understand-anything): whole-dir symlinks, upstream-installer
            # layout; no front-matter validation so upstream cannot wedge eval
            skills.symlinkDirs = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "symlink each skill dir whole (for skills carrying scripts/subdirs)";
            };
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "session variables exported while this plugin is enabled";
            };
            opencodePlugin = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "path to a .mjs plugin opencode loads (skips skills symlink for opencode)";
            };
            piPackage = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "pi package spec (e.g. git:github.com/...) loading this plugin (skips skills symlink for pi)";
            };
          };
        }
      );
      default = { };
      description = "plugins loaded into the agents";
    };

    mcp.servers = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      defaultText = lib.literalExpression "universal set (git, fetch, everything, playwright, deepwiki, nixos, context7, grep_app, codegraph)";
      description = "canonical MCP server set, rendered into every enabled agent; consumer and host-level programs.mcp.servers additions land everywhere";
    };

    # providers are openai-compatible grids; secrets never enter the store -
    # only env-var NAMES are rendered, the consumer exports the values
    providers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "render this provider into the enabled agents";
            };
            baseUrl = lib.mkOption {
              type = lib.types.str;
              description = "openai-compatible base URL";
            };
            apiKeyEnv = lib.mkOption {
              type = lib.types.str;
              description = "env-var name holding the API key (never the key itself)";
            };
            timeout = lib.mkOption {
              type = lib.types.int;
              default = 600000;
              description = "request timeout in ms";
            };
            models = lib.mkOption {
              type = lib.types.listOf (
                lib.types.either
                  lib.types.str
                  (lib.types.submodule {
                    options = {
                      id = lib.mkOption {
                        type = lib.types.str;
                        description = "model id as served by the provider";
                      };
                      contextWindow = lib.mkOption {
                        type = lib.types.nullOr lib.types.int;
                        default = null;
                        description = "context window in tokens surfaced to the agents (omp shows 128k otherwise)";
                      };
                      maxTokens = lib.mkOption {
                        type = lib.types.nullOr lib.types.int;
                        default = null;
                        description = "max output tokens";
                      };
                    };
                  })
              );
              default = [ ];
              description = "model ids served by this provider; each is a bare id or an attrset with optional contextWindow/maxTokens";
            };
            defaultModel = lib.mkOption {
              type = lib.types.str;
              description = "bare model id used as the agents' default";
            };
          };
        }
      );
      default = { };
      description = "LLM providers rendered into every enabled agent";
    };
    defaultProvider = lib.mkOption {
      type = lib.types.str;
      description = "provider name (key in s-ai.providers) the agents default to; set alongside your providers";
    };

    # prompt set: numbered markdown files combined into every agent's
    # AGENTS.md; add your own dirs, override builtin files by name
    prompts.builtin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "ship the builtin prompt set (git, before-you-code, code-comments, docs, nix)";
    };
    prompts.dirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = [ ./my-prompts ];
      description = "extra prompt directories appended after the builtin set; same-named files override builtin ones (01-git.md in your dir replaces ours), everything sorts by filename";
    };

    theme.palette = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        base00 = "181616";
        base01 = "282727";
        base02 = "393836";
        base03 = "625e5a";
        base04 = "737c73";
        base05 = "c5c9c5";
        base06 = "c8c093";
        base07 = "c5c9c5";
        base08 = "c4746e";
        base09 = "b6927b";
        base0A = "c4b28a";
        base0B = "8a9a7b";
        base0C = "8ea4a2";
        base0D = "8ba4b0";
        base0E = "a292a3";
        base0F = "b98d7b";
      };
      description = "palette driving the derived omp theme; pass config.lib.stylix.colors as-is (extra keys are ignored) or a plain base16 set (hex, no #)";
    };
  };

  imports = map (f: import f { inherit inputs; }) [
    ./agents/omp.nix
    ./agents/pi.nix
    ./agents/opencode.nix
  ];

  config = {
    # builtin plugins; enables use mkDefault so a user's plain assignment wins
    s-ai.plugins = {
      # required: the shared skill set and nothing else
      core = {
        enable = lib.mkDefault true;
        skills.dir = lib.mkDefault ../plugins/core/skills;
        skills.copyAllFiles = lib.mkDefault true;
      };
      # lazy-dev skill; opencode loads the .mjs plugin, pi the package,
      # omp only the symlinked skills
      ponytail = {
        enable = lib.mkDefault true;
        skills.dir = lib.mkDefault "${inputs.ponytail}/skills";
        skills.agents = lib.mkDefault [ "omp" ];
        env.PONYTAIL_DEFAULT_MODE = lib.mkDefault "ultra";
        opencodePlugin = lib.mkDefault "${inputs.ponytail}/.opencode/plugins/ponytail.mjs";
        piPackage = lib.mkDefault "git:github.com/DietrichGebert/ponytail";
      };
      # frontend-design skill, vendored from claude-code
      claude-code = {
        enable = lib.mkDefault true;
        skills.dir = lib.mkDefault "${inputs.claude-code}/plugins/frontend-design/skills";
      };
      # worktree/tmux workflow skills
      workmux = {
        enable = lib.mkDefault false;
        skills.dir = lib.mkDefault "${inputs.workmux}/skills";
      };
    };

    s-ai.mcp.servers = universalServers;

    # canonical registry: opencode consumes it via its MCP integration, and
    # the pi/omp agent renders read the merged set so host-level additions
    # (e.g. a bitbucket server) land in every agent
    programs.mcp = {
      enable = lib.mkIf (
        cfg.agents.opencode.enable || cfg.agents.omp.enable || cfg.agents.pi.enable
      ) true;
      servers = cfg.mcp.servers;
    };

    # plugin envs apply while the plugin is enabled
    home.sessionVariables = lib.concatMapAttrs (_: p: p.env) enabledPlugins;
  };
}
