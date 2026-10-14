# opencode agent: settings via the upstream home-manager module, plus the
# oh-my-openagent (OMO) plugin wiring and the rendered AGENTS.md and skills.
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.s-ai.agents.opencode;

  combinedSystemPrompt = import ../lib/prompts.nix lib (
    lib.optional config.s-ai.prompts.builtin ../../prompts ++ config.s-ai.prompts.dirs
  );
  skillsMod = import ../lib/skills.nix {
    inherit lib;
    plugins = lib.filterAttrs (_: p: p.enable) config.s-ai.plugins;
  };

  providers = lib.filterAttrs (_: p: p.enable) config.s-ai.providers;
  defaultProvider = config.s-ai.providers.${config.s-ai.defaultProvider};
  defaultModel = "${config.s-ai.defaultProvider}/${defaultProvider.defaultModel}";

  omoPkg = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.oh-my-opencode;
  bashPermissions = builtins.fromJSON (builtins.readFile ../bash-permissions.json);

  # .mjs plugins from enabled s-ai plugins (e.g. ponytail)
  opencodePlugins = lib.filter (p: p != null) (
    lib.mapAttrsToList (_: p: p.opencodePlugin) (
      lib.filterAttrs (_: p: p.enable && p.opencodePlugin != null) config.s-ai.plugins
    )
  );

  # Unified OMO config (~/.omo/omo.jsonc). The file is a read-only hm store
  # symlink, so OMO's migrations cannot write it and wedge their journal on
  # every boot - pre-mark each migration id in _migrations (new ids show up
  # as "[config-migration] ... not applied" toasts; grep MIGRATION_ID in the
  # oh-my-openagent dist).
  omoConfig = {
    "$schema" =
      "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/omo.schema.json";
    "[opencode]" = {
      default_run_agent = "sisyphus";
      team_mode = {
        enabled = true;
        tmux_visualization = true;
      };
      agents =
        lib.genAttrs
          [
            "sisyphus"
            "metis"
            "prometheus"
            "atlas"
            "hephaestus"
            "oracle"
            "momus"
            "explore"
            "librarian"
            "multimodal-looker"
            "sisyphus-junior"
          ]
          (
            name:
            {
              model = defaultModel;
            }
            // lib.optionalAttrs (name == "hephaestus") { allow_non_gpt_model = true; }
          );
    };
    # every id oh-my-openagent's registry currently defines (grep
    # MIGRATION_ID in its dist when a new one toasts): the config is a
    # read-only store symlink, and none of the migrations change our shape -
    # they target legacy imperative configs
    _migrations = [
      "2026-07-codex-config-jsonc"
      "2026-07-opencode-config-unification"
      "2026-08-reasoning-unification"
      "2026-09-category-deep-split"
      "2026-09-harness-native-rename"
      "2026-09-subscription-provider-rename"
    ];
  };
in
{
  options.s-ai.agents.opencode = {
    omo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "oh-my-openagent plugin (Sisyphus agent system, team mode, subagents)";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "attrs deep-merged last into programs.opencode.settings";
    };
    extraOmoConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "attrs deep-merged last into the OMO ~/.omo/omo.jsonc config";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      OPENCODE_ENABLE_EXA = 1;
    };

    home.packages = [
      omoPkg
      pkgs.nodejs
      pkgs.bun
    ];

    home.file =
      skillsMod.files
      // {
        ".config/opencode/AGENTS.md".text = combinedSystemPrompt;
      }
      // lib.optionalAttrs cfg.omo {
        # oh-my-openagent's lib dir - read-only, fine as a store symlink
        ".config/opencode/node_modules/oh-my-openagent".source = "${omoPkg}/lib/oh-my-opencode";
      };

    # OMO rewrites ~/.omo/omo.jsonc at runtime and its migration system
    # resolves the file to run/config-mark migrations. A `home.file` store
    # symlink is read-only and resolves to a /nix/store path, so both the
    # migration write and OMO's canonical-path check fail. Copy a writable
    # regular file during activation instead (same pattern as omp's config):
    # the _migrations markers then persist and OMO skips already-run
    # migrations.
    home.activation.omoConfig = lib.mkIf (cfg.omo) {
      before = [ ];
      after = [ "writeBoundary" ];
      data = ''
        run mkdir -p "$HOME/.omo"
        run install -m 600 ${pkgs.writeText "omo.jsonc" (builtins.toJSON (lib.recursiveUpdate omoConfig cfg.extraOmoConfig))} "$HOME/.omo/omo.jsonc"
      '';
    };

    programs.opencode = {
      enable = true;
      package = inputs.opencode-vim.packages.${pkgs.stdenv.hostPlatform.system}.default;
      enableMcpIntegration = true;
      web = {
        enable = lib.mkDefault false;
        extraArgs = [ "--mdns" ];
      };
      settings = lib.mkMerge [
        {
          autoupdate = true;
          model = defaultModel;
          # opencode provider format: { name, modalities, ... } per model
          provider = lib.mapAttrs (name: p: {
            npm = "@ai-sdk/openai-compatible";
            name = name;
            options = {
              baseURL = p.baseUrl;
              apiKey = "{env:${p.apiKeyEnv}}";
              timeout = p.timeout;
            };
            models = lib.listToAttrs (
              map (
                m:
                let
                  id = if builtins.isString m then m else m.id;
                in
                lib.nameValuePair id ({
                  name = id;
                  modalities = {
                    input = [
                      "text"
                      "image"
                    ];
                    output = [ "text" ];
                  };
                }
                // lib.optionalAttrs (if builtins.isString m then false else m.contextWindow != null) {
                  contextWindow = if builtins.isString m then null else m.contextWindow;
                })
              ) p.models
            );
          }) providers;
          permission = {
            read = {
              "*" = "allow";
              ".env*" = "ask";
              "**/.env*" = "ask";
            };
            grep = {
              "*" = "allow";
              ".env*" = "ask";
              "**/.env*" = "ask";
            };
            glob = "allow";
            list = "allow";
            bash = bashPermissions;
          };
          plugin = opencodePlugins ++ lib.optional cfg.omo "oh-my-openagent";
          default_agent = "sisyphus";
          agent = {
            sisyphus = {
              prompt = ''
                Commit hygiene: NEVER set --author to yourself or add Co-authored-by trailers for the AI agent. Always commit as the repository's configured git identity. Never commit or push without explicit user approval.
              '';
            };
          };
        }
        cfg.extraSettings
      ];
      tui = {
        vim_system_clipboard_register = true;
        vim_escape_sequence = "jk";
        vim_enter_submit = true;
        vim_insert_after_submit = true;
        scroll_acceleration.enabled = true;
        plugin = opencodePlugins ++ lib.optional cfg.omo "oh-my-openagent";
      };
    };
  };
}
