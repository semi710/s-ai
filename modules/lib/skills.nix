# Skills wiring: turn enabled plugins into per-agent home.file mappings.
#
# Each plugin owns a skills dir; `skills.agents` decides which agents get the
# skills symlinked (a plugin loaded through an agent's own mechanism, like
# ponytail via opencode's .mjs or pi's package system, excludes that agent so
# skills are not double-registered). `skills.copyAllFiles` marks authored
# skills: every file ships (checklists, templates) and front matter is
# validated; vendored inputs ship SKILL.md only and get the duplicate check.
{
  lib,
  plugins,
}:
let
  # plugins that ship skills to at least one agent
  skillPlugins = lib.filterAttrs (_: p: p.enable && p.skills.dir != null) plugins;

  # names of skill dirs inside one plugin (directories only)
  namesIn =
    dir:
    lib.filter (name: (builtins.readDir dir).${name} == "directory") (
      lib.attrNames (builtins.readDir dir)
    );

  # file mappings for one plugin into one agent's skills prefix
  pluginFiles =
    prefix: p:
    let
      dir = p.skills.dir;
      names = namesIn dir;
    in
    if p.skills.copyAllFiles then
      lib.listToAttrs (
        lib.concatMap (
          name:
          map (f: {
            name = "${prefix}/${name}/${f}";
            value.source = "${dir}/${name}/${f}";
          }) (lib.attrNames (builtins.readDir "${dir}/${name}"))
        ) names
      )
    else
      lib.listToAttrs (
        map (name: {
          name = "${prefix}/${name}/SKILL.md";
          value.source = "${dir}/${name}/SKILL.md";
        }) names
      );

  # eval-time skill hygiene, ported from the ndots validate-skills practice:
  # authored skills (copyAllFiles) must open with a front-matter fence on
  # line 1, close it, and carry non-empty name + description. Vendored
  # skills only get the duplicate-name check, so upstream breakage cannot
  # wedge eval.
  frontMatterLines =
    text:
    let
      lines = map (l: lib.removeSuffix "\r" l) (lib.splitString "\n" text);
      body = lib.tail lines;
      fenceIdx = lib.lists.findFirstIndex (l: lib.hasPrefix "---" l) (-1) body;
    in
    if lib.head lines != "---" || fenceIdx < 0 then null else lib.take fenceIdx body;

  hasField = fm: field: lib.any (l: lib.match "${field}:[[:space:]]*[^[:space:]].*" l != null) fm;

  skillError =
    dir: name:
    let
      fm = frontMatterLines (builtins.readFile "${dir}/${name}/SKILL.md");
    in
    if fm == null then
      "front matter fence missing or unclosed"
    else if !hasField fm "name" then
      "missing non-empty name field"
    else if !hasField fm "description" then
      "missing non-empty description field"
    else
      null;

  badAuthoredSkills = lib.concatMap (
    pname:
    let
      p = skillPlugins.${pname};
    in
    if !p.skills.copyAllFiles then
      [ ]
    else
      map (name: "${pname}/${name}: ${skillError p.skills.dir name}") (
        lib.filter (name: skillError p.skills.dir name != null) (namesIn p.skills.dir)
      )
  ) (builtins.attrNames skillPlugins);

  # skill names an agent's symlinked set would load, plugin-prefixed
  namesForAgent =
    agent:
    lib.concatMap (
      pname:
      let
        p = skillPlugins.${pname};
      in
      if builtins.elem agent p.skills.agents then
        map (name: "${pname}/${name}") (namesIn p.skills.dir)
      else
        [ ]
    ) (builtins.attrNames skillPlugins);

  duplicatedName =
    agent:
    let
      loaded = namesForAgent agent;
    in
    lib.findFirst (n: lib.count (x: x == n) loaded > 1) null loaded;

  # file mappings for one agent: union of the plugins targeting it
  filesFor =
    agent: prefix:
    lib.foldlAttrs (
      acc: pname: p:
      if builtins.elem agent p.skills.agents then acc // (pluginFiles prefix p) else acc
    ) { } skillPlugins;

  rendered = {
    # ~/.config/opencode/skills/
    files = filesFor "opencode" ".config/opencode/skills";

    # ~/.pi/agent/skills/
    piFiles = filesFor "pi" ".pi/agent/skills";

    # ~/.omp/agent/skills/
    ompFiles = filesFor "omp" ".omp/agent/skills";
  };
in
lib.throwIf (badAuthoredSkills != [ ])
  "s-ai: skills with invalid SKILL.md front matter: ${toString badAuthoredSkills}"
  (
    lib.throwIf (duplicatedName "opencode" != null)
      "s-ai: duplicate skill name for opencode: ${duplicatedName "opencode"}"
      (
        lib.throwIf (duplicatedName "pi" != null)
          "s-ai: duplicate skill name for pi: ${duplicatedName "pi"}"
          (
            lib.throwIf (
              duplicatedName "omp" != null
            ) "s-ai: duplicate skill name for omp: ${duplicatedName "omp"}" rendered
          )
      )
  )
