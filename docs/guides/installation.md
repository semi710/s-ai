# Installation

s-ai is a nix flake exposing a home-manager module plus agent binaries.

## As a home-manager module

```nix
# flake.nix
{
  inputs.s-ai.url = "github:semi710/s-ai";
  # ...
  outputs = { s-ai, ... }: {
    # add to your home-manager modules
  };
}
```

```nix
# home-manager config
{ ... }: {
  imports = [ s-ai.homeModules.s-ai ];
  # then configure providers etc. (see Options)
}
```

The module closes over its own inputs (agent versions, skill sources), so
consumers need no specialArgs.

## Imperatively (without a nix config)

```bash
nix run github:semi710/s-ai#omp        # oh-my-pi
nix run github:semi710/s-ai#pi         # pi
nix run github:semi710/s-ai#opencode   # opencode
```

Each binary runs from its own store path with the shared reads (skills,
prompts) available. This is the "no declarative config" path - you lose the
shared-render conveniences but still get the packaged agents.

## Local checkout while developing

s-ai is consumed by ndots via a `path:` input. Refresh after local s-ai
edits with:

```bash
nix flake lock --update-input s-ai   # in the consumer repo (e.g. ndots)
```

Because s-ai is a path input, its narHash is pinned in the consumer's
`flake.lock`; the read command advances it.

## First build note

omp compiles from source (bun2nix) on the first build (~20 min). Subsequent
builds reuse the store. Plan a binary cache before sharing s-ai widely.