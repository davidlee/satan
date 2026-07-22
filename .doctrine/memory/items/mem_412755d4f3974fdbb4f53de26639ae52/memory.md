# SATAN ingest cursor require

# dl-satan-ingest-cursor feature is not auto-loaded

## Summary

`dl-satan-ingest-cursor` is **not loaded** in a fresh running emacs
(`(featurep 'dl-satan-ingest-cursor)` ⇒ nil). Only `dl-satan-broker` requires
it, lazily (on a tick). So a bare `emacsclient -e
'(dl-satan-ingest-cursor-backlog-depth)'` errors `void`.

External callers (e.g. waybar scripts) must require it first:

```sh
emacsclient --eval '(progn (require (quote dl-satan-ingest-cursor)) (plist-get (dl-satan-ingest-cursor-backlog-depth) :total))'
```

Doing `plist-get … :total` in the eval form returns a bare int, keeping the bash
guard identical to satan-inbox.

## Context

Verified 2026-06-10 while building the `custom/satan-backlog` waybar widget. The
read fn returns `(:focus N :browser N :content N :total N)`. Widget script:
`~/.config/waybar/scripts/satan-backlog.sh` (see [[mem.fact.waybar.deploy]]).
