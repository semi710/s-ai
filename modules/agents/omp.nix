# oh-my-pi agent: renders the canonical layer into omp's formats (config via
# the upstream home-manager module, mcp.json/models.yml/themes/keybindings
# as store symlinks - omp reads them read-only).
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.s-ai.agents.omp;

  combinedSystemPrompt = import ../lib/prompts.nix lib (
    lib.optional config.s-ai.prompts.builtin ../../prompts ++ config.s-ai.prompts.dirs
  );
  skillsMod = import ../lib/skills.nix {
    inherit lib;
    plugins = lib.filterAttrs (_: p: p.enable) config.s-ai.plugins;
  };

  themes = import ../theme.nix {
    inherit lib;
    omp = inputs.omp;
    # accepts any palette attrset - raw config.lib.stylix.colors or a plain
    # base16 set; only the baseXX hex keys feed the theme
    palette = lib.filterAttrs (n: _: builtins.match "base[0-9A-F]{2}" n != null) config.s-ai.theme.palette;
  };

  # enabled providers, rendered into omp's models.yml
  providers = lib.filterAttrs (_: p: p.enable) config.s-ai.providers;
  defaultProvider = config.s-ai.providers.${config.s-ai.defaultProvider};

  # omp's mcp.json schema is strict (additionalProperties: false): stdio
  # takes command/args/env, http takes type/url/headers. Strip the pi-only
  # keys (lifecycle, directTools, autoApprove) and translate `{env:VAR}`
  # values to omp's env-name form.
  ompServer =
    server:
    let
      env = lib.mapAttrs (_: v: lib.removeSuffix "}" (lib.removePrefix "{env:" v)) (
        lib.filterAttrs (_: v: v != null) (server.env or { })
      );
    in
    if (server.type or "stdio") == "stdio" then
      {
        inherit (server) command;
      }
      // lib.optionalAttrs (server.args or [ ] != [ ]) { inherit (server) args; }
      // lib.optionalAttrs (env != { }) { inherit env; }
    else
      {
        type = "http";
        url = server.url;
      }
      // lib.optionalAttrs ((server.headers or { }) != { }) { inherit (server) headers; };
in
{
  options.s-ai.agents.omp = {
    prewalk = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "strong model plans, then the smol role runs implementation from the first edit/write (one-way handoff; cheaper, can lose quality mid-task)";
    };
    advisor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "second-opinion reviewer on stop (needs an explicit advisor model role)";
    };
    memory = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "local SQLite per-project recall/retain (mnemopi) + post-stop lesson capture";
    };
    # advisor/prewalk have no model in their builtin fallback chains, so the
    # roles stay unarmed unless set explicitly (e.g. "<provider>/<fast-model>")
    advisorModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "model id for omp's advisor role (second-opinion reviewer); null leaves the role unarmed";
    };
    smolModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "model id for omp's smol role (prewalk execution, commit messages, background tasks); null leaves the role unarmed";
    };
    keybindings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
      default = {
        # vim-style select navigation; alt-chords dodge type-to-search which
        # eats plain j/k (user bindings replace defaults, so the arrows must
        # stay listed). app.display.reset drops its default alt+l so tmux's
        # alt+h/l -> Left/Right translation stays consistent outside tmux too
        # (display reset is unused).
        "tui.select.up" = [
          "up"
          "alt+k"
        ];
        "tui.select.down" = [
          "down"
          "alt+j"
        ];
        "app.display.reset" = [ ];
      };
      description = "Action-id to chord(s) mapping written to ~/.omp/agent/keybindings.yml; upstream reads no keybindings object from config.yml, so this file is the only remap channel";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "attrs deep-merged last into programs.omp.settings; overrides any default (e.g. modelRoles.smol)";
    };
  };

  imports = [ inputs.omp.homeManagerModules.default ];

  config = lib.mkIf cfg.enable {
    # python for omp's eval tool (without it, eval runs JavaScript only)
    home.packages = [ pkgs.python3 ];

    programs.omp = {
      enable = true;
      settings = lib.mkMerge [
        {
          # same default model as the other agents (provider grid)
          modelRoles = {
            default = "${config.s-ai.defaultProvider}/${defaultProvider.defaultModel}";
          }
          // lib.optionalAttrs (cfg.advisorModel != null) { advisor = cfg.advisorModel; }
          // lib.optionalAttrs (cfg.smolModel != null) { smol = cfg.smolModel; };
          defaultThinkingLevel = "medium";
          # replaces vim-motions-pi; no jk escape, plain Escape only
          tui.vimMode = true;
          # pi-style status line: `π > INSERT > ⬢ model > 📁 path > ⑂ git ▶─ctx─`
          statusLine.preset = "default";
          # pi-style composer: framed horizontal rules, status line at bottom
          composer.shape = "pi";
          # skip the one-time setup wizard; nerd glyphs
          setupVersion = 2;
          symbolPreset = "nerd";

          # dark is derived from the palette; light stays upstream
          theme.dark = "s-ai-dark";
          theme.light = "s-ai-light";
        }
        # behavior toggles
        (lib.optionalAttrs cfg.memory {
          memory.backend = "mnemopi";
          autolearn.enabled = true;
        })
        (lib.optionalAttrs cfg.advisor {
          advisor.enabled = true;
        })
        (lib.optionalAttrs cfg.prewalk {
          prewalk.enabled = true;
        })
        # user overrides win
        cfg.extraSettings
      ];
    };

    home.file = skillsMod.ompFiles // {
      # same content as the other agents' AGENTS.md - omp loads it as user-level context
      ".omp/agent/AGENTS.md".text = combinedSystemPrompt;

      # derived themes land where omp discovers custom themes by name
      ".omp/agent/themes/s-ai-dark.json".text = builtins.toJSON themes.dark;
      ".omp/agent/themes/s-ai-light.json".text = builtins.toJSON themes.light;

      # declarative remaps (see s-ai.agents.omp.keybindings); upstream
      # reads this file, never a keybindings object in config.yml
      ".omp/agent/keybindings.yml".text = lib.generators.toYAML { } cfg.keybindings;

      # rendered from the merged programs.mcp.servers set, so host-level
      # additions land in omp too. omp reads it read-only, a store
      # symlink is fine.
      ".omp/agent/mcp.json".text = builtins.toJSON {
        mcpServers = lib.mapAttrs (_: ompServer) config.programs.mcp.servers;
      };

      # omp reads this read-only, a store symlink is fine (unlike config.yml).
      # omp: plain string is an env-var name (pi needed a "$" prefix)
      ".omp/agent/models.yml".text = lib.generators.toYAML { } {
        providers = lib.mapAttrs (_: p: {
          baseUrl = p.baseUrl;
          api = "openai-completions";
          apiKey = p.apiKeyEnv;
          models = map (
            m:
            if builtins.isString m then
              { id = m; }
            else
              {
                id = m.id;
              }
              // lib.optionalAttrs (m.contextWindow != null) { inherit (m) contextWindow; }
              // lib.optionalAttrs (m.maxTokens != null) { inherit (m) maxTokens; }
          ) p.models;
        }) providers;
      };
    };
  };
}
