# SATAN — Noctalia plugin

Desktop surfaces for SATAN in the [Noctalia](https://noctalia.dev) shell.

| Field | Value |
| --- | --- |
| ID | `davidlee/satan` |
| Entries | Bar widget: `inbox` |
| Requires | a running Emacs server with `satan` loaded; `emacsclient` on `PATH`; the Umbriel compositor (click only) |

## `inbox` widget

Shows the SATAN inbox's unread count (`satan-inbox-unread-count`), polled over
`emacsclient` every 10 s. The count is owned by Emacs; the plugin only displays it.

| State | Bar |
| --- | --- |
| unread > 0 | `inbox` glyph + count |
| 0 unread | hidden |
| Emacs unreachable / bad reply | `inbox-off` glyph, no count |

Left click focuses the dedicated `SATAN inbox` Emacs frame, or creates it. The frame
is launched with `umbriel msg spawn`, so it gets an activation token, and so focus;
a later click finds it by title, re-shows the inbox in it
(`satan-inbox-show-in-frame`, since its buffer may have changed) and focuses it
with `window-focus:<id>`.
Force a poll: `noctalia msg plugin davidlee/satan:inbox all refresh`.

## Install

```sh
noctalia msg plugins source add satan path ~/dev/satan/noctalia
noctalia msg plugins enable davidlee/satan
```

Then add the **SATAN inbox** widget to a bar in Settings → Bar. `.luau` edits
hot-reload; manifest edits need a config reload.

## Develop

Logic lives in `lib/inbox.luau` (pure), tested by `test/inbox_test.luau`;
`just test` runs it, `just lint` runs `luau-analyze` over both. The entry
script requires `./lib/inbox.luau` (Noctalia needs the extension); the test
requires `../lib/inbox` (the `luau` CLI rejects it).
