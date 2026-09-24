#!/usr/bin/env python3
"""value_baseline.py — SL-220 Phase 0 ranking-snapshot instrument.

Throwaway, stdlib-only. Two subcommands over `doctrine survey` output:

  snapshot <out.json> [--neutral]
      Runs a survey against the live project (or, with --neutral, against a
      throwaway copy of `.doctrine` with `[priority.coefficients] value` set
      to 0) and saves `[rank, id, score]` rows to <out.json>. The live
      corpus is never touched by --neutral (a fresh temp copy is scored
      instead; verify with a before/after tree-hash comparison).

  diff <a.json> <b.json> [--top N]
      Rank-move report between two snapshots: entries entering/leaving the
      top-N window, position deltas, score deltas. N defaults to 20 (the
      `doctrine survey` default page size); `--top 0` means uncapped.

Design: .doctrine/slice/220/design.md §5. Not product surface — neither
subcommand commits anything; the operator reviews and commits the JSON +
`.doctrine/slice/220/phase0-baseline.md` report.

CLI drift disclosure: design §5 cites `doctrine reports survey`; the shipped
verb is `doctrine survey --json` (confirmed live 2026-07-17). This script
uses the real verb.

Both scripts in this pair (this one and migrate_value_facets.py) refuse to
run against a dirty git tree, so an operator always has a clean revert path.
The dirty-tree check is duplicated verbatim in both files on purpose: each
throwaway script is meant to be copy-pasted / run standalone without needing
its sibling on the path — see the hand-back notes for the DRY tradeoff.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DOCTRINE_TOML_REL = Path(".doctrine") / "doctrine.toml"
PROJECT_MARKER = ".project"  # matches src/root.rs default_markers()


def doctrine_bin() -> str:
    """Locate the doctrine binary: `DOCTRINE_BIN` env override, else PATH."""
    return os.environ.get("DOCTRINE_BIN", "doctrine")


def refuse_if_dirty(cwd: Path) -> None:
    """Refuse to proceed if `cwd`'s git tree carries staged or unstaged
    changes — the precondition that gives an operator a clean revert path.
    """
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        print(
            f"refusing to run: could not determine git status at {cwd} ({exc}) "
            "— this script requires a git working tree",
            file=sys.stderr,
        )
        sys.exit(1)
    if result.stdout.strip():
        print(
            "refusing to run: git working tree is dirty (staged and/or "
            "unstaged changes present) — commit or clean first so this "
            "run has a clean revert path:\n" + result.stdout,
            file=sys.stderr,
        )
        sys.exit(1)


def run_survey(extra_args: list[str]) -> dict:
    cmd = [doctrine_bin(), "survey", "--json", "--limit", "0", *extra_args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"doctrine survey failed ({' '.join(cmd)}):", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def rows_to_entries(survey_json: dict) -> list[list]:
    """`[rank, id, score]` triples, rank = 1-based position in the survey's
    already-sorted importance order.
    """
    return [
        [i + 1, row["id"], row["score"]]
        for i, row in enumerate(survey_json.get("rows", []))
    ]


def build_neutral_root(live_root: Path, tmp_root: Path) -> None:
    """Copy `.doctrine` (which nests `doctrine.toml`) into `tmp_root`, then
    zero the value coefficient THERE via `doctrine config set` (never
    touching the live corpus). A `.project` marker file lets `config set`
    (which has no -p/--path flag) auto-detect `tmp_root` purely from cwd.
    """
    live_doctrine = live_root / ".doctrine"
    if not live_doctrine.is_dir():
        print(f"refusing: no .doctrine/ under {live_root}", file=sys.stderr)
        sys.exit(1)
    # `state/` is gitignored RUNTIME (dispatch worktrees, caches — can be
    # tens of GB and is irrelevant to scoring); never copy it into the
    # neutral root. Authored corpus + comparisons + config are what score.
    shutil.copytree(
        live_doctrine,
        tmp_root / ".doctrine",
        symlinks=True,
        ignore=shutil.ignore_patterns("state"),
    )
    (tmp_root / PROJECT_MARKER).write_text("")

    cmd = [doctrine_bin(), "config", "set", "coefficients.value", "0", "-P"]
    result = subprocess.run(cmd, cwd=tmp_root, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"doctrine config set failed in neutral copy: {result.stderr}", file=sys.stderr)
        sys.exit(1)


def cmd_snapshot(args: argparse.Namespace) -> None:
    cwd = Path.cwd()
    refuse_if_dirty(cwd)

    if args.neutral:
        with tempfile.TemporaryDirectory(prefix="value-baseline-neutral-") as tmp:
            tmp_root = Path(tmp)
            build_neutral_root(cwd, tmp_root)
            survey_json = run_survey(["-p", str(tmp_root)])
    else:
        survey_json = run_survey([])

    entries = rows_to_entries(survey_json)
    out_path = Path(args.out)
    out_path.write_text(json.dumps(entries, indent=2) + "\n")
    print(f"wrote {len(entries)} rows to {out_path}")


def load_entries(path: str) -> dict[str, tuple[int, float]]:
    """id -> (rank, score), from a `[[rank, id, score], ...]` snapshot file."""
    with open(path, encoding="utf-8") as fh:
        raw = json.load(fh)
    return {entry[1]: (entry[0], entry[2]) for entry in raw}


def cmd_diff(args: argparse.Namespace) -> None:
    a = load_entries(args.a)
    b = load_entries(args.b)
    requested = 20 if args.top is None else args.top
    top_n = max(len(a), len(b)) if requested == 0 else requested

    top_a = {id_ for id_, (rank, _) in a.items() if rank <= top_n}
    top_b = {id_ for id_, (rank, _) in b.items() if rank <= top_n}

    entering = sorted(top_b - top_a, key=lambda i: b[i][0])
    leaving = sorted(top_a - top_b, key=lambda i: a[i][0])
    common = sorted(set(a) & set(b))
    added = sorted(set(b) - set(a))
    removed = sorted(set(a) - set(b))

    print(f"Baseline diff: {args.a} -> {args.b}  (top {top_n})")
    print()
    print(f"Entering top-{top_n} ({len(entering)}):")
    for id_ in entering:
        rank, score = b[id_]
        print(f"  {id_:<12} rank {rank:>4}  score {score:.4f}")
    print()
    print(f"Leaving top-{top_n} ({len(leaving)}):")
    for id_ in leaving:
        rank, score = a[id_]
        print(f"  {id_:<12} rank {rank:>4}  score {score:.4f}")
    print()

    movers = []
    for id_ in common:
        rank_a, score_a = a[id_]
        rank_b, score_b = b[id_]
        movers.append((id_, rank_a, rank_b, rank_a - rank_b, score_a, score_b, score_b - score_a))
    movers.sort(key=lambda m: abs(m[3]), reverse=True)

    print(f"Position deltas (common to both, {len(movers)} entries, sorted by |Δrank|):")
    for id_, rank_a, rank_b, drank, score_a, score_b, dscore in movers:
        direction = "up" if drank > 0 else ("down" if drank < 0 else "unchanged")
        print(
            f"  {id_:<12} rank {rank_a:>4} -> {rank_b:>4} ({direction} {abs(drank)})"
            f"   score {score_a:.4f} -> {score_b:.4f} (Δ{dscore:+.4f})"
        )
    print()

    print(f"Added ({len(added)}, only in {args.b}): {', '.join(added) if added else '(none)'}")
    print(f"Removed ({len(removed)}, only in {args.a}): {', '.join(removed) if removed else '(none)'}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p_snap = sub.add_parser("snapshot", help="save a [rank, id, score] ranking snapshot")
    p_snap.add_argument("out", help="output JSON path")
    p_snap.add_argument("--neutral", action="store_true", help="score with [priority.coefficients] value = 0")
    p_snap.set_defaults(func=cmd_snapshot)

    p_diff = sub.add_parser("diff", help="rank-move report between two snapshots")
    p_diff.add_argument("a", help="baseline snapshot JSON")
    p_diff.add_argument("b", help="comparison snapshot JSON")
    p_diff.add_argument("--top", type=int, default=None, help="top-N window (default 20; 0 = uncapped)")
    p_diff.set_defaults(func=cmd_diff)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
