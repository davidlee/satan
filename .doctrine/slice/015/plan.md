# Implementation Plan SL-015: Corpus relocation: SATAN model-facing corpus leaves ~/notes for a standalone repo

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Cite entities by padded id (SL-020, REQ-059); phases as PHASE-01,
     criteria as EN-1/EX-1/VT-1/VA-1/VH-1. See .doctrine/glossary.md § reference forms. -->

## Overview

Four phases. One is the design, two are the moves, one is the record.

PHASE-01 carries the whole design payload — the three named roots and the 25
rewired sites — and carries none of the risk, because both new defaults still
resolve exactly where the paths resolve today. PHASE-02 and PHASE-03 are the two
live moves, deliberately separated. PHASE-04 sweeps documentation and memory.

## Sequencing & Rationale

**Why the refactor lands before anything moves.** The design's premise (P1) is
that the relocation is a *consequence* of naming the concept. PHASE-01 tests
that premise: if naming the roots is done properly, the move reduces to one
default value, and VA-1 proves the rewire is behaviour-free by diffing all 25
resolved paths before and after. A rewire that cannot pass that check is a
rewire that changed something it shouldn't have — better to discover that with
the trees still in place.

**Why state moves before the corpus.** Two reasons, one practical and one
structural. Practically, `runs/` is 9.4k files and 145M of the 145M — moving it
first leaves ~250K of authored content, which is what makes PHASE-03's history
split fast to inspect and lets `~/satan` ship with no `.gitignore` at all
(design P5). Structurally, the two moves are independent: the state split stands
on its own merits (design D3) even if the corpus relocation were abandoned
tomorrow, so it should not be entangled with it.

**Why PHASE-01's transitional defaults are not the fallback design D2
rejects.** D2 rejects resolving two candidate paths and preferring whichever
exists, because that turns a botched move into a silent misconfiguration of the
model's own framing. PHASE-01 resolves exactly one path — the current one. There
is always a single answer to "where does the corpus live"; PHASE-03 changes that
answer once, atomically, and if it fails the failure is loud.

**Why there is a phase for the record.** Eight authored corpus files tell the
model where its corpus is (design F2/D6); those are PHASE-03 exit criteria
because a stale one is a live defect, not a documentation lag. PHASE-04 is the
rest: docs, the memory corpus, and the whole-`$HOME` sweep (design R5) that
catches a consumer the survey missed. The sweep is the only check that can find
an unknown unknown, which is why it is a phase gate and not a footnote.

## Notes

**Live writers are the sequencing constraint** (design F1). Both move phases
open with quiesce and close with restart-and-observe. `satan-{tick,motd,morning}
.timer`, `satan-attrd.service` and waybar's wpm module all write into the trees
being moved; a rename under a live writer strands rows in a directory nothing
reads again.

**The `~/notes` working tree is a hard gate** (EN-2 of PHASE-03, design R3).
Four modified and 31 untracked files sit under `satan/` today. A history
operation over a dirty tree loses them silently.

**OQ-1 must resolve before any `git rm`** (EN-3). `git subtree split` is
built in; `git filter-repo` is not installed here. Whether subtree yields usable
history over a corpus whose commits are daily `git add .` snapshots is an
empirical question, and the answer decides the tool. Both options must be
exhausted while the subtree is still in place.

**CHR-003 is deliberately stale, not forgotten.** The punted `satan-patcher`
keeps working because PHASE-03 EX-7 retargets the systemd `Environment=` pin
that overrides its built-in default. Only an unpinned invocation dangles.
