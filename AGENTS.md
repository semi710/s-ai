# AGENTS.md

Instructions for AI agents working in this repo. s-ai is a flake library
consumed by other people's configs (ndots, testhost), so its defaults and
modules affect everyone downstream.

## Ask before committing

Show the diff and wait for explicit approval before every commit, and again
before pushing. "Do the commit" covers the changes you were shown, not
anything you added afterwards. When in doubt, leave the work uncommitted
and say so.

## Find the established way before inventing one

Before adding a mechanism, check how the problem is already solved:

- the tool's own flake/nixpkgs recipe (e.g. workmux's flake installs its
  completions with `installShellCompletion` in postInstall)
- nixpkgs conventions and helpers (`installShellFiles`, `overrideAttrs`
  postInstall, `passthru`, buildEnv merging) instead of ad-hoc
  `runCommand` wrappers
- the consuming config's conventions when the change affects them

A wrapper derivation that reproduces what a package can ship itself is a
smell. Prefer the standard practice, and say which precedent you followed
in the commit or PR.

## Modules are consumed by others

- s-ai modules must stay opt-in: never force a package, provider, or plugin
  on consumers (no tool packages in `home.packages` from a module, no
  work-specific config). The consumer's package set and config own those
  choices; the module declares options.
- Keep defaults boring and composable: `mkDefault` for enables, escape
  hatches (`extraSettings`, `extraPackages`) for overrides.
- Anything host- or user-specific belongs in the consumer (see the "Work
  tier belongs to the consumer" decision).

## Verify, then report

- Evaluate/build the affected outputs before claiming something works
  (`nix flake check`, the testhost, or the consumer's config when the
  change reaches it).
- Report what you did not verify, and do not describe a change as
  "tested" when only an eval passed.
