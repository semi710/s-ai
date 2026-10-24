# claude agent (Claude Code): renders the canonical layer into claude's
# formats - settings.json for endpoint/auth/model, ~/.claude.json merged for
# user-scope MCP, CLAUDE.md and skills as store symlinks. claude speaks the
# Anthropic Messages API against a single endpoint, so the default provider
# drives everything and it must declare protocol "anthropic".
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
  cfg = config.s-ai.agents.claude;

  combinedSystemPrompt = import ../lib/prompts.nix lib (
    lib.optional config.s-ai.prompts.builtin ../../prompts ++ config.s-ai.prompts.dirs
  );
  skillsMod = import ../lib/skills.nix {
    inherit lib;
    plugins = lib.filterAttrs (_: p: p.enable) config.s-ai.plugins;
  };

  defaultProvider = config.s-ai.providers.${config.s-ai.defaultProvider};

  # programs.mcp.servers -> claude's ~/.claude.json mcpServers shape. The
  # home-manager submodule default-fills enabled/env/headers/url onto every
  # entry, so whitelist per shape instead of stripping: stdio takes
  # command/args/env, http takes type "http"/url/headers. {env:VAR} values
  # become claude's ${VAR} substitution.
  toClaudeServer =
    server:
    let
      remote = (server.type or "stdio") != "stdio";
      env = lib.optionalAttrs ((server.env or { }) != { }) {
        env = lib.mapAttrs (
          _: v:
          if lib.hasPrefix "{env:" v && lib.hasSuffix "}" v then
            "\${" + lib.removeSuffix "}" (lib.removePrefix "{env:" v) + "}"
          else
            v
        ) server.env;
      };
    in
    (
      if remote then
        {
          type = "http";
          inherit (server) url;
        }
        // lib.optionalAttrs ((server.headers or { }) != { }) { inherit (server) headers; }
      else
        {
          inherit (server) command;
        }
        // lib.optionalAttrs ((server.args or [ ]) != [ ]) { inherit (server) args; }
    )
    // env;

  claudeServers = lib.mapAttrs (_: toClaudeServer) config.programs.mcp.servers;

  settings = lib.recursiveUpdate {
    env = {
      ANTHROPIC_BASE_URL = defaultProvider.baseUrl;
      # grid model ids are not claude aliases, so the built-in haiku fallback
      # for background/fast ops would 404 - use the same model
      ANTHROPIC_MODEL = defaultProvider.defaultModel;
      ANTHROPIC_SMALL_FAST_MODEL = defaultProvider.defaultModel;
    };
    model = defaultProvider.defaultModel;
    # key stays out of the store: claude runs this and reads the value the
    # consumer exports under providers.<name>.apiKeyEnv
    apiKeyHelper = "printenv ${defaultProvider.apiKeyEnv}";
  } cfg.extraSettings;

  mcpFile = pkgs.writeText "claude-mcp.json" (builtins.toJSON claudeServers);
  initialClaudeJson = pkgs.writeText "claude.json" (builtins.toJSON { mcpServers = claudeServers; });

  # ~/.claude.json is claude's live state file (projects, onboarding) with
  # user-scope mcpServers mixed in - a store symlink would freeze its writes
  # and a blind copy would clobber the state, so merge only our key
  mergeScript = pkgs.writeShellApplication {
    name = "claude-json-mcp-merge";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      target="$HOME/.claude.json"
      if [ -f "$target" ]; then
        jq --slurpfile mcp ${mcpFile} '.mcpServers = $mcp[0]' "$target" > "$target.s-ai.tmp"
        mv "$target.s-ai.tmp" "$target"
      else
        install -m 600 ${initialClaudeJson} "$target"
      fi
    '';
  };
in
{
  options.s-ai.agents.claude = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.claude-code;
      defaultText = lib.literalExpression "pkgs.claude-code";
      description = "claude-code package (unfree); allow it in your nixpkgs.config or substitute your own build";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "attrs deep-merged last into ~/.claude/settings.json";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.elem "anthropic" defaultProvider.protocols;
        message = "s-ai: agents.claude needs providers.${config.s-ai.defaultProvider}.protocols to include \"anthropic\" (claude speaks the Anthropic Messages API against one endpoint)";
      }
    ];

    home.packages = [ cfg.package ];

    home.file = skillsMod.claudeFiles // {
      ".claude/CLAUDE.md".text = combinedSystemPrompt;
      ".claude/settings.json".text = builtins.toJSON settings;
    };

    home.activation.claudeMcp = {
      before = [ ];
      after = [ "writeBoundary" ];
      data = "run ${mergeScript}/bin/claude-json-mcp-merge";
    };
  };
}
