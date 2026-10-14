# Scratch consumer for testing s-ai changes: prove the module evals and
# builds standalone, and flip options here to see their effect.
# Build: nix build .#test-home
{
  ...
}:
{
  home.username = "tester";
  home.homeDirectory = "/home/tester";
  home.stateVersion = "25.05";

  # provider config is always consumer-side; secrets stay in your env/sops.
  # this one is a dummy local endpoint so the test host never talks to
  # anything real
  s-ai.providers.example = {
    baseUrl = "http://localhost:8080/v1";
    apiKeyEnv = "EXAMPLE_API_KEY";
    models = [
      "model-large"
      "model-fast"
    ];
    defaultModel = "model-large";
  };
  s-ai.defaultProvider = "example";

  # exercise the advisor/smol role options
  s-ai.agents.omp.advisorModel = "example/model-large";
  s-ai.agents.omp.smolModel = "example/model-fast";

  # option playground - uncomment to test:
  # s-ai.plugins.workmux.enable = true;
  # s-ai.plugins.core.enable = false;
  # s-ai.agents.omp.prewalk = false;
  # s-ai.agents.omp.extraSettings.modelRoles.smol = "example/model-fast";
  # s-ai.theme.palette = config.lib.stylix.colors;  # (in a stylix config)
  # s-ai.prompts.dirs = [ ./my-prompts ];           # extra rules in AGENTS.md
  # s-ai.prompts.builtin = false;                   # ship only your own set
}
