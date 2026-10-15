# pi agent: renders the canonical layer into pi's formats (settings via the
# upstream home-manager module, mcp.json as a store symlink).
{
  inputs,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.s-ai.agents.pi;

  combinedSystemPrompt = import ../lib/prompts.nix lib (
    lib.optional config.s-ai.prompts.builtin ../../prompts ++ config.s-ai.prompts.dirs
  );
  skillsMod = import ../lib/skills.nix {
    inherit lib;
    plugins = lib.filterAttrs (_: p: p.enable) config.s-ai.plugins;
  };

  providers = lib.filterAttrs (_: p: p.enable) config.s-ai.providers;
  defaultProvider = config.s-ai.providers.${config.s-ai.defaultProvider};

  # pi packages from plugins that load through pi's package system
  piPackages = lib.filter (p: p != null) (
    lib.mapAttrsToList (_: p: p.piPackage) (
      lib.filterAttrs (_: p: p.enable && p.piPackage != null) config.s-ai.plugins
    )
  );

  # programs.mcp.servers is multi-client/opencode flavored; pi's builtin mcp
  # extension wants its own vocabulary, so translate per server here
  toPiServer =
    server:
    let
      # pi validates: url servers take type "http"|"streamable-http" or no
      # type at all, command servers "stdio" or none; the canonical "remote"
      # type (and its enabled flag) must be translated away
      remote = (server.type or "stdio") != "stdio";
      base =
        if remote then
          { inherit (server) url; }
          // lib.optionalAttrs ((server.headers or { }) != { }) { inherit (server) headers; }
        else
          lib.filterAttrs (n: _: !builtins.elem n [ "type" "lifecycle" "autoApprove" ]) server;
      # pi's native mcp reads ${VAR}; the canonical layer stores
      # opencode-flavored {env:VAR}
      piEnv = lib.optionalAttrs (server ? env) {
        env = lib.mapAttrs (
          _: v:
          if lib.hasPrefix "{env:" v && lib.hasSuffix "}" v then
            "\${" + lib.removeSuffix "}" (lib.removePrefix "{env:" v) + "}"
          else
            v
        ) server.env;
      };
    in
    lib.filterAttrs (_: v: v != null) ({ exposure = "direct"; } // base // piEnv);
in
{
  options.s-ai.agents.pi = {
    vimMotions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "vim-motions-pi plugin (our fork): jk escape, yank syncs to the system clipboard via OSC 52";
    };
    clipboardCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression "lib.getExe pkgs.copy";
      description = "OSC 52 clipboard command for vim-motions-pi (e.g. your copy tool); null disables clipboard sync";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "attrs deep-merged last into programs.pi-coding-agent.settings";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = lib.optionalAttrs (cfg.vimMotions && cfg.clipboardCommand != null) {
      # vim-motions-pi: two-key escape sequence (e.g. jk, jj)
      VIM_MOTION_PI_ESCAPE_SEQUENCE = "jk";
      # vim-motions-pi: yank syncs to the system clipboard (default is "off",
      # which silently disables the command below)
      VIM_MOTION_PI_CLIPBOARD = "yank";
      VIM_MOTION_PI_CLIPBOARD_COMMAND = cfg.clipboardCommand;
    };
    home.file = skillsMod.piFiles // {
      # render pi's mcp.json ourselves - its onboarding-written file rots
      # after GC. reads the same merged programs.mcp.servers as the other
      # agents, so host-level additions land in pi too.
      ".pi/agent/mcp.json".text = builtins.toJSON {
        mcpServers = lib.mapAttrs (_: toPiServer) config.programs.mcp.servers;
      };
    };

    programs.pi-coding-agent = {
      enable = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
      # put the clipboard tool's package on PATH yourself when you set
      # clipboardCommand (it is consumer-specific, e.g. pkgs.copy)
      extraPackages = [
        pkgs.nodejs
        pkgs.bun
      ];
      settings = lib.mkMerge [
        {
          # same default model as the other agents (provider grid)
          defaultProvider = config.s-ai.defaultProvider;
          defaultModel = defaultProvider.defaultModel;
          defaultThinkingLevel = "medium";
          theme = "dark";
          # plugin packages from s-ai.plugins (e.g. ponytail)
          packages = piPackages ++ lib.optional cfg.vimMotions "${inputs.vim-motions-pi}";
        }
        cfg.extraSettings
      ];
      # ~/.pi/agent/AGENTS.md - same content as the other agents' AGENTS.md
      context = combinedSystemPrompt;
    };

    # providers rendered in pi's models.json shape; the "$" prefix makes pi
    # read the env var (pi treats plain strings as literal keys)
    programs.pi-coding-agent.models.providers = lib.mapAttrs (_: p: {
      baseUrl = p.baseUrl;
      api = "openai-completions";
      apiKey = "$" + p.apiKeyEnv;
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
}
