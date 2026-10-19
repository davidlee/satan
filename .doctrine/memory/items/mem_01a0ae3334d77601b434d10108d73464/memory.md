# patch_job_create: repo is a runner name, mode is the acting run mode, scope is the runner's

The `patch_job_create` contract as of the malebolge runner (SL-023); the
earlier prompts got it wrong for months (found closing [[CHR-004]], corrected
by [[SL-025]]).

## repo is a runner config name

`repo` is a `[repo.<name>]` key in the runner's config, not a path. The runner
resolves it; an unknown name is refused `invalid_request`. One job edits one
repo: mechanism (`satan`) and corpus (`satan-corpus`) need separate jobs — see
[[mem.concept.satan.three-roots]].

## mode is the acting run mode, stamped by Emacs

`mode` is not a tool argument. `satan-tools-patch.el` takes it from the tool
ctx `:mode-name` (DEC-068). A call with no acting mode (no ctx, e.g. a bare
`emacsclient` call) is refused and nothing is sent. MCP sessions submit as
`interactive`.

## Per-mode scope is enforced by the runner at submit

Each `[mode.<m>]` carries required `repos` and `allowed_paths` (`"*"` =
unbounded). A submit whose repo or paths fall outside is refused
`invalid_request`, naming what the mode allows (DEC-069; malebolge
`src/runner/protocol.ts` `withinModeScope`, commit `226b27c`, live from
SL-025's cutover). Emacs does no scope check: one enforcer.

## allowed_paths is repo-relative, and only that

Trailing `/` is a prefix match; without one it is an exact match; no globs.
Nothing expands `~`, so a home-anchored entry like `"~/satan-corpus/tools/"`
is refused (malebolge `src/runner/classify.ts`, `normaliseAllowedEntry`
refuses absolute, `..`, empty and whitespace-padded entries).
