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

  providers = lib.filterAttrs (
    _: p: p.enable && builtins.elem "openai" p.protocols
  ) config.s-ai.providers;
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

  # stylix's opencode target dropped the theme name into the v1
  # programs.opencode.tui; v2 warns when tui is set and reads the theme
  # from themes.<name> instead
  tuiTheme =
    if
      config.programs ? opencode
      && config.programs.opencode ? tui
      && config.programs.opencode.tui ? theme
    then
      config.programs.opencode.tui.theme
    else if
      config.programs ? opencode
      && config.programs.opencode ? themes
      && config.programs.opencode.themes ? stylix
    then
      "stylix"
    else
      null;

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
    extraCliSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "attrs deep-merged last into the rendered v2 cli.json";
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
        # v2 reads cli.json; our home-manager pin renders only the v1-named
        # tui.json, so the terminal-client config is rendered here until
        # home-manager ships programs.opencode.cli
        ".config/opencode/cli.json".text = builtins.toJSON (
          lib.recursiveUpdate
            (
              {
                "$schema" = "https://opencode.ai/v2/cli.json";
                plugins = opencodePlugins ++ lib.optional cfg.omo "oh-my-openagent";
                scroll.acceleration = true;
                vim = true;
                vim_escape_sequence = "jk";
                vim_enter_submit = true;
                vim_insert_after_submit = true;
                vim_system_clipboard_register = true;
              }
              // lib.optionalAttrs (tuiTheme != null) {
                theme = if builtins.isAttrs tuiTheme then tuiTheme else { name = tuiTheme; };
              }
            )
            cfg.extraCliSettings
        );
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
      package =
        let
          # darwin runs the latest ocv release with the CLI renamed back at
          # build: the fork bakes `ocv` into the binary (build.ts consts ->
          # OPENCODE_CLI_NAME/PRODUCT_NAME), which moves config/auth/data to
          # ~/.config/ocv. Its nix/hashes.json is stale (hash bot stalled at
          # the port), so node_modules carries a fresh hash. Other systems
          # stay on the consistent opencode-named pin.
          pkg =
            if pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then
              (pkgs.callPackage "${inputs.opencode-vim-latest}/nix/opencode.nix" {
                node_modules = pkgs.callPackage "${inputs.opencode-vim-latest}/nix/node_modules.nix" {
                  rev = inputs.opencode-vim-latest.shortRev or "dirty";
                  hash = "sha256-Mxx5tPv6cCF+FTOIuMaXNEr1lLBODf7KuzAsEnKSn2E=";
                };
              }).overrideAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace packages/cli/script/build.ts \
                    --replace-fail 'const cliName = "ocv"' 'const cliName = "opencode"' \
                    --replace-fail 'const productName = "ocv"' 'const productName = "opencode"'
                '';
              })
            else
              inputs.opencode-vim.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        # upstream build.ts ad-hoc re-signs darwin binaries (macOS 27+) but
        # stdenvNoCC has no codesign on PATH; sigtool provides codesign,
        # cctools its codesign_allocate helper
        if pkgs.stdenv.hostPlatform.isDarwin then
          pkg.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              pkgs.darwin.sigtool
              pkgs.cctools
            ];
          })
        else
          pkg;
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
                  mm = if builtins.isString m then null else m;
                in
                lib.nameValuePair id (
                  {
                    name = id;
                    modalities = {
                      input = [
                        "text"
                        "image"
                      ];
                      output = [ "text" ];
                    };
                  }
                  # opencode v2 renamed contextWindow -> limit; the schema
                  # requires both context and output, so models missing either
                  # fall back to opencode's models.dev catalog
                  // lib.optionalAttrs (mm != null && mm.contextWindow != null && mm.maxTokens != null) {
                    limit = {
                      context = mm.contextWindow;
                      output = mm.maxTokens;
                    };
                  }
                )
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
    };
  };
}
