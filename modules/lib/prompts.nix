# Combine numbered markdown files from prompt directories into one ordered
# system-prompt string, written to every agent's AGENTS.md so the same rules
# apply everywhere. Directories merge in order: a file with the same name in
# a later directory replaces the earlier one, then everything sorts by
# filename and concatenates.
lib:
dirs:
let
  mdFiles =
    dir:
    lib.filter (f: lib.hasSuffix ".md" f) (
      builtins.attrNames (builtins.readDir dir)
    );

  # filename -> path, later dirs win on name collisions
  merged = lib.foldl (acc: dir: acc // (lib.genAttrs (mdFiles dir) (f: dir + "/${f}"))) { } dirs;

  sorted = lib.sort lib.lessThan (builtins.attrNames merged);
in
lib.concatMapStringsSep "\n\n" (filename: builtins.readFile merged.${filename}) sorted
