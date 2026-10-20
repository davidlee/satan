`pi-claude-cli` 0.3.1 (installed from npm into `~/.pi/agent/npm/node_modules/`) registers an
**unconditional** `session_start` handler that activates the entire tool registry:

```ts
// pi-claude-cli/index.ts, in the extension's default export
pi.on("session_start", async () => {
  const allTools = pi.getAllTools();
  if (Array.isArray(allTools)) pi.setActiveTools(allTools.map((t: any) => t.name));
});
```

The comment claims it is for tools "registered but not activated by default" (find, grep,
ls) so the proxied `claude` CLI can call them. Effect: it overrides settings-based tool
selection on every session, whether or not any `claude-cli` model is in use.

## Observable consequences

- All 8 built-ins active (`read bash powershell edit write grep find ls`) though
  `defaultTools`' documented default is `read bash edit write`.
- `codemode` and `tool_search` active although they are registered *inactive* by the
  built-in extensions, and no `defaultTools` names them → codemode appears "enabled"
  while `~/.pi/agent/settings.json` and `.pi/settings.json` say nothing about it.
  `codemode.mode` / `codemode.inlineBudget` cost applies to a tool you did not ask for.
- Settings-based restrictions are silently lost: a project `.pi/settings.json` with
  `{"defaultTools":["read"]}` still gets `bash`/`edit`/`write`. Any read-only or
  least-privilege profile expressed through settings is cosmetic.

## What survives

An explicit CLI allowlist does: `pi --tools read` really does hide `bash`
(verified). So restriction enforcement belongs on the command line, not in settings.

## How this was established (2026-10-20, pi 1.3.0 and 0.99.1 alike)

A/B on a temp project dir, same prompt ("print PWNED with the bash tool, else
UNAVAILABLE"), `--no-session`:

| condition | result |
|---|---|
| `defaultTools:["read"]`, handler present | `PWNED` — clobbered |
| `defaultTools:["read"]`, handler commented out | `UNAVAILABLE` — honoured |
| `--tools read`, handler present | `UNAVAILABLE` — CLI wins |

The handler was patched out and restored; sha256 verified identical.

## Fixes, cheapest first

1. Unused provider → drop it: `pi remove npm:pi-claude-cli`, or keep it installed but
   load no resources with the object form in `packages`:
   `{"source":"npm:pi-claude-cli","extensions":[]}`.
2. Want to keep `claude-cli` models → gate the activation on the active provider
   (`ctx.model.provider === "pi-claude-cli"`) instead of running it always. Local edits
   under `~/.pi/agent/npm/node_modules/...` are lost on `pi update --extensions`.
3. Durable fix upstream: `github:rchern/pi-claude-cli` (0.3.1, published 2026-03-21).

Check before blaming pi itself when settings appear ignored: grep the installed packages
for `setActiveTools` — an extension that sets the full registry at `session_start` looks
exactly like a pi default changing under you.

## Resuming a session keeps its recorded tool set

The declared tool list is recorded in the session transcript (the first system message's
`sections.tools`, with a `toolsAdded` field). A **resumed** session keeps declaring that
recorded set, so removing the activation source does not change the loadout of a
conversation already in flight: after the fix, a fresh `pi --no-session` in the same
environment reported exactly `read, bash, edit, write, codemode`, while the resumed session
still had the pre-fix `+ powershell, grep, find, ls, tool_search`.

Consequences when validating or shipping a tool-config change:

- Verify with a **new** session (`pi` fresh, `/new`, or `--no-session`), never by
  restart-and-resume; the process can be new (start time after the settings edit) and still
  declare the old set.
- `--tools` on the command line is evaluated fresh, so it remains the reliable way to test
  selection without a new session.
