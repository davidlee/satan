The notes corpus is the user's and read-only to SATAN; a path-taking read tool is a new input class for the broker's notes module, and the only path-taking one.

Decision: `notes_read :path` accepts a notes-root-relative path only. It errors — never returns an empty result — on a non-string or empty path, an absolute path, any path with a `..` component, and any path whose truename is not inside the expanded `satan-tools-notes-root` (the root itself, a symlink escape, a missing file, a non-file).

Why not a `:pattern` on the arg schema: a regex over a path string cannot decide containment — `.`/`..` segments, symlinks and the root itself all defeat it. The check belongs in the handler, at the point where the path is resolved.

Why refusal is an error and not an empty result: an empty result is indistinguishable from a legitimately empty file, and would let a caller conclude the corpus is empty — the SL-015 rule that a wrong-but-readable answer is worse than an error (`.doctrine/slice/015/design.md`).

Applies to any future path-taking tool over a SATAN-readable root, not only notes.

## How it was decided

Two candidate policies. (a) Trust the model: accept any path the arg validator sees as a string and let the caller find out. (b) Confine: accept only what resolves inside the notes root, and refuse everything else.

The validator (satan-tool--validate-args, satan-tools.el:144) can enforce type and an elisp regex `:pattern`, but a regex over a path string cannot decide containment — `.` and `..` segments, symlinks and the root itself all defeat it. So the decision is a resolver in the handler.

What can go wrong under (a): the notes corpus is the user's whole home-adjacent note tree, but the broker's process can read anything the user can. A prompt-injected or merely confused model could ask for `~/.ssh/id_ed25519` or `../../secrets` and the tool would answer. No existing notes tool takes a path input, so this class of input is new to the module (notes_at_satan_scan takes no path; org_read_context takes a fixed scope enum).

What (b) costs: nothing real. Every path the tool is *for* is under the root, and refusal is a clear error string.

Sub-decision: refusal as error vs as an empty result. An empty result is indistinguishable from 'the file exists and is empty' and would let a caller conclude the corpus is empty — the SL-015 principle that a wrong-but-readable answer is worse than an error.