# Troubleshooting

Real issues hit while running s-ai-managed agents, and their root causes.

## omp/opencode: "legacy configuration changes were not applied: Migration target is not an omo config path"

**Symptom:** every boot of opencode/OMO toasts

```
[config-migration] legacy configuration changes were not applied: Migration target is not an omo config path: /nix/store/...-hm_.omoomo.jsonc
```

**Root cause:** `~/.omo/omo.jsonc` was a read-only **store symlink** (created by a
`home.file` entry). OMO's migration engine resolves the symlink to a
`/nix/store/...` path, which is not the canonical `$HOME/.omo/omo.jsonc`, so
its `writerInput` path check throws before it even looks at `_migrations`.

**Fix (in s-ai):** `~/.omo/omo.jsonc` is now written as a **writable regular file**
via `home.activation` (`install -m 600 <store> "$HOME/.omo/omo.jsonc"`), not a
`home.file` symlink - the same pattern omp's upstream module uses for
`config.yml`. With a writable, canonical-path file, OMO sees the pre-marked
`_migrations` and skips them.

**If you still see it after upgrading:** you likely have a stale symlink left
over from an old generation. Remove it; the next `home-manager switch`
recreates it as a writable file:

```bash
rm -f ~/.omo/omo.jsonc
home-manager switch   # or: just deploy / nh home switch
```

## pi: "server X needs either 'command' (stdio) or 'url' (streamable HTTP)"

**Symptom:**
```
Warning: MCP servers need attention:
  config: ... mcp.json: server "context7" needs either "command" (stdio) or "url" (streamable HTTP)
```

**Root cause:** the canonical MCP format uses `type = "remote"` for http
servers, but pi's validator only accepts `type = "http"`/`"streamable-http"`
or **no `type` at all** for url servers, and `"stdio"`/none for command
servers. `"remote"` matched neither, so pi rejected servers that already had
`url` present.

**Fix (in s-ai):** pi's `mcp.json` render translates remote entries to
`{ url, headers? }` (dropping `type`) before merging pi's own keys, and
strips `type` on stdio entries. Host-level additions (e.g. `bitbucket`) pass
through the same translation.

## omp: "Python eval unavailable (Python executable not found on PATH)"

**Symptom:** in the omp startup banner,
```
Warning: Python eval unavailable (Python executable not found on PATH); eval will run JavaScript only.
```

**Root cause:** omp's eval tool found no `python3` on PATH.

**Fix:** omp's module now adds `pkgs.python3` to `home.packages` so the eval
tool uses its full Python backend. Nothing to do on the consumer side.

## omp shows a fixed 128k context even though the grid serves more

**Symptom:** omp's status line / model selector shows `128k` (or `14%/128k`)
for a model whose real window is larger (e.g. `glm-latest` = 400k).

**Root cause:** omp's default context window for any openai-compatible model
is 128k. Without an explicit `contextWindow` in the model entry, it never
knows the real window.

**Fix:** set `contextWindow`/`maxTokens` on the model in `s-ai.providers.<name>.models`
(from the grid's `/v1/models`, fields `max_input_tokens`/`max_output_tokens`):

```nix
models = [
  { id = "glm-latest"; contextWindow = 400000; maxTokens = 32000; }
];
```

## Adding a model / provider requires knowledge of the served window

The grid's `/v1/models` endpoint is authoritative for context windows. When
tuning a provider, re-check it:

```bash
curl -s -H "Authorization: Bearer $API_KEY" https://grid.example/v1/models \
  | jq -r '.data[] | "\(.id): \(.max_input_tokens)/\(.max_output_tokens)"'
```