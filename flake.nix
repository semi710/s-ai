{
  description = "s-ai - coding agents (opencode, omp, pi) with shared skills, prompts, MCP and providers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # oh-my-pi - pi-mono fork with native vim mode, MCP, and LSP-edits.
    # Bump with: `nix flake update omp` (theme.nix reads
    # packages/tui/src/theme/light.json from this input; a failed eval after a
    # bump means the theme sources moved upstream).
    omp.url = "github:can1357/oh-my-pi";

    # pi + oh-my-opencode packages
    llm-agents.url = "github:numtide/llm-agents.nix";

    # opencode (vim-mode fork) is fetched as a pre-built release binary;
    # see packages/opencode-release.nix for version + per-platform hashes

    # vim motions for pi's input box. plain upstream v0.2.0 (bar-cursor PR
    # merged); no fork. transcript copy/selection is pi-copy-mode's job, and
    # the few scroll keys outside copy mode come from pi's keybindings.json
    # so this stays on upstream main.
    vim-motions-pi.url = "github:kepatrick/vim-motions-pi";
    vim-motions-pi.flake = false;

    # ponytail - lazy-dev skill plugin (vendored source, not a full flake)
    ponytail.url = "github:DietrichGebert/ponytail";
    ponytail.flake = false;

    # workmux skills (worktree/tmux workflow)
    workmux.url = "github:raine/workmux";

    # external skill sources, tracked rev+narHash by the lock
    claude-code.url = "github:anthropics/claude-code";
    claude-code.flake = false;
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # manual list, not nix-systems/default: that includes x86_64-darwin,
      # which llm-agents publishes no packages for; this is the actual
      # support intersection of the agent inputs
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # The module closes over this flake's own inputs, so consumers need no
      # specialArgs: `imports = [ s-ai.homeModules.s-ai ];`
      flake.homeModules.s-ai = import ./modules { inherit inputs; };

      perSystem =
        {
          inputs',
          system,
          ...
        }:
        let
          # claude-code is unfree; allow just it here so the module's test
          # build and `nix build .#claude-code` work. Consumers of
          # homeModules.s-ai allow it in their own nixpkgs.config (or set
          # agents.claude.package).
          pkgs = import "${inputs.nixpkgs}" {
            inherit system;
            config.allowUnfreePredicate = p: inputs.nixpkgs.lib.getName p == "claude-code";
          };
          # scratch consumer build, proving the module works standalone:
          # `nix build .#test-home`
          testHome = inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              inputs.self.homeModules.s-ai
              ./testhost/home.nix
            ];
          };
        in
        {
          # agent binaries, usable without the module
          packages = {
            omp = inputs'.omp.packages.default;
            pi = inputs'.llm-agents.packages.pi;
            opencode = (pkgs.callPackage ./packages/opencode-release.nix { });
            oh-my-opencode = inputs'.llm-agents.packages.oh-my-opencode;
            claude-code = pkgs.claude-code;
            default = inputs'.omp.packages.default;
            test-home = testHome.activationPackage;
          };

          # full build of every render and agent binary; slow on first run
          # (omp compiles), instant afterwards from the local store
          checks.home-activation = testHome.activationPackage;

          # docs site: `nix run .#docs -- serve` / `-- build`
          # (CI builds the same site with mkdocs-material, see docs.yml)
          apps.docs = {
            type = "app";
            program = "${
              pkgs.python3.withPackages (ps: [
                ps.mkdocs
                ps.mkdocs-material
              ])
            }/bin/mkdocs";
          };

          formatter = pkgs.nixfmt;
        };
    };
}
