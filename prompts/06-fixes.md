## Fixes

### Derive the fix from the root cause
A correct diagnosis is worthless if the fix inherits the shape of the code it replaces. Never start from "make the existing approach work" - that is how symptom patches grow regexes, special cases and guards. Once the cause is known, design the minimal fix that makes the cause impossible, even when that means replacing an existing approach entirely.

### Read nondeterminism from its source
Before pattern-matching nondeterministic values (sandbox paths, temp dirs, build IDs) with regexes or wildcards, ask where the value is actually known. Anything opaque from outside a build is usually available inside it: cwd, env vars, phase-shared shell state. Query the source of truth; never regex its shadow.

### A fix that needs a guard is a smell
If a patch requires a watchdog next to it - a grep after a sed, a fallback, a separate verification step - it is fighting the grain. Prefer primitives that verify themselves (`--replace-fail` over `--replace`, assertions over post-hoc checks). If the guard cannot be made redundant, the fix is at the wrong layer.

### Fail loud, never degrade silently
Flags that downgrade failures to warnings (deprecated `--replace`, `|| true`, force flags) let broken fixes ship green. Always take the strict variant: drift must surface as a loud build error when it happens, not as a runtime bug the user finds.
