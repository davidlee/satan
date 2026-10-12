`~/satan-corpus/justfile`'s `commit` recipe is `git reset; git add .; git ci -m $(date +%F)`.
The corpus is routinely dirty with SATAN's own runtime writes (inbox.org, motd.txt,
goad data, hippocampus notes, proposals), so `just commit` folds them into whatever
an agent meant to land, under a date-only message.

For an agent's deliberate corpus edit (a slice phase, a tool description fix),
commit the file by path with a descriptive message instead:

    git -C ~/satan-corpus add tools/<file>.md
    git -C ~/satan-corpus commit -m "tools: …"

Leave the unrelated dirty state for the user. Plans that say "commit with
`just commit`" mean "commit in the corpus repo" (SL-021 PHASE-05 EX-2, RV-022 F-3).
See [[mem.concept.satan.three-roots]].
