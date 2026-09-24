#!/usr/bin/env python3
"""migrate_estimate_facets.py — SL-222 one-shot `[estimate]` facet migration.

Throwaway, stdlib-only (tomllib to parse; NO write-capable TOML dependency
— the emitted session is hand-rendered text, and the strip is line-level
text surgery proven correct by a tomllib re-parse equality check, never
assumed). Neither `--check` nor `--execute` commits anything; the operator
reviews and commits. Refuses to run against a dirty git tree (clean revert
path).

Five stages (design .doctrine/slice/222/design.md §5):

  1. Scan   — every `[estimate]` table under the authored entity dirs
              (`.doctrine/` entity TOMLs; comparisons/, state/, and any
              other non-entity tree are excluded BY CONSTRUCTION — this
              script only ever walks the entity-kind directories named in
              KIND_DIRS below, never `.doctrine/` wholesale).
  2. Emit   — one session file per run in `.doctrine/comparisons/`, one
              anchor row per facet that needs (re-)importing. A run that
              imports nothing writes no file.
  3. Verify — shell out to the doctrine binary to prove the emitted
              corpus still parses/resolves (exit-0 gate) BEFORE any strip.
  4. Census — every scanned facet accounted exactly once: imported /
              already-imported / re-imported (superseding). Aborts
              pre-strip if the counts don't reconcile.
  5. Strip  — (--execute only) remove each `[estimate]` table by line-level
              text surgery; per file, verify via tomllib re-parse that the
              stripped document equals the pre-strip document minus the
              `estimate` key. A file that fails this check is left
              untouched and reported; the run still exits non-zero.

Divergence from the SL-220 template (migrate_value_facets.py):

  F-7 (RV-282) — `--check` is truly non-mutating. The template's `--check`
  writes the session file before verifying (its own docstring admits it).
  Here `--check` computes the would-be rows and the census entirely in
  memory and writes NOTHING — no session file, no strip, tree byte-identical
  before/after. Only `--execute` emits the session file, runs the
  doctrine-binary parse gate, reconciles the census (abort pre-strip on
  mismatch), and strips.

  Estimate payload — the `[estimate]` table carries `lower`/`upper` (not
  `magnitude`); the wire row emits `est_lower`/`est_upper` fields with
  `magnitude` absent.

  Domain/frame — `domain = "estimate"`, `frame = "cost-anchor"` (not
  `"value"` / `"value-anchor"`).

  Never `admission = "pin"` (E9) — under no input does the script emit a
  pin. The template never emitted it either, but this script enforces the
  invariant explicitly: the render function never writes an admission field.

  Parse gate runs FOR REAL — MIGRATE_SKIP_PARSE_GATE is NOT defined. The
  post-flip binary (PHASE-06 landed: `COMPARISON_VERSION = 3`, `est_lower`/
  `est_upper` columns, `cost-anchor` frame, `rater = migrated` parse) can
  parse the v3 migrated rows this script emits. The escape hatch from the
  SL-220 template (pre-flip fixture exercise) is unnecessary now; it is
  omitted. If a production need arises, set DOCTRINE_BIN to a compatible
  binary — the parse gate runs unconditionally through the real binary.
"""

from __future__ import annotations

import argparse
import math
import os
import re
import subprocess
import sys
import tomllib
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path

# Directory -> (canonical-id prefix, filename stem), mirroring the
# `Kind { dir, prefix, stem }` table src/*.rs defines per entity kind.
# `[estimate]` capture is optional per kind, so this table intentionally
# covers every entity kind — a facet can exist (and need migrating) on
# any kind. Filename shape per kind is `<dir>/<NNN>/<stem>-<NNN>.toml`.
KIND_DIRS: list[tuple[str, str, str]] = [
    (".doctrine/slice", "SL", "slice"),
    (".doctrine/spec/product", "PRD", "spec"),
    (".doctrine/spec/tech", "SPEC", "spec"),
    (".doctrine/requirement", "REQ", "requirement"),
    (".doctrine/adr", "ADR", "adr"),
    (".doctrine/policy", "POL", "policy"),
    (".doctrine/standard", "STD", "standard"),
    (".doctrine/review", "RV", "review"),
    (".doctrine/rec", "REC", "rec"),
    (".doctrine/revision", "REV", "revision"),
    (".doctrine/rfc", "RFC", "rfc"),
    (".doctrine/backlog/issue", "ISS", "backlog"),
    (".doctrine/backlog/improvement", "IMP", "backlog"),
    (".doctrine/backlog/chore", "CHR", "backlog"),
    (".doctrine/backlog/risk", "RSK", "backlog"),
    (".doctrine/backlog/idea", "IDE", "backlog"),
    (".doctrine/knowledge/assumption", "ASM", "record"),
    (".doctrine/knowledge/decision", "DEC", "record"),
    (".doctrine/knowledge/question", "QUE", "record"),
    (".doctrine/knowledge/constraint", "CON", "record"),
    (".doctrine/knowledge/evidence", "EVD", "record"),
    (".doctrine/knowledge/hypothesis", "HYP", "record"),
    (".doctrine/knowledge/concept", "CPT", "record"),
    (".doctrine/concept-map", "CM", "concept-map"),
]

COMPARISONS_DIR = Path(".doctrine") / "comparisons"
ESTIMATE_HEADER_RE = re.compile(r"^\[estimate\]\s*(#.*)?$")
ESTIMATE_LOWER_RE = re.compile(r"^\s*lower\s*=")
ESTIMATE_UPPER_RE = re.compile(r"^\s*upper\s*=")
SECTION_HEADER_RE = re.compile(r"^\[")
BASIS_SOURCE_RE = re.compile(r"^facet \[estimate\] (\S+)")


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


# ---------------------------------------------------------------------------
# Stage 1: scan
# ---------------------------------------------------------------------------


@dataclass
class Facet:
    relpath: str  # POSIX-style, relative to root — the scan/basis/census key
    abs_path: Path
    canonical_id: str
    lower: float
    upper: float


def scan_facets(root: Path) -> list[Facet]:
    facets: list[Facet] = []
    for dir_rel, prefix, stem in KIND_DIRS:
        kind_dir = root / dir_rel
        if not kind_dir.is_dir():
            continue
        for child in sorted(kind_dir.iterdir()):
            if not (child.is_dir() and child.name.isdigit()):
                continue
            entity_file = child / f"{stem}-{child.name}.toml"
            if not entity_file.is_file():
                continue
            with open(entity_file, "rb") as fh:
                doc = tomllib.load(fh)
            estimate_table = doc.get("estimate")
            if not isinstance(estimate_table, dict):
                continue
            raw_lower = estimate_table.get("lower")
            raw_upper = estimate_table.get("upper")
            if raw_lower is None or raw_upper is None:
                print(
                    f"abort: [estimate] table in {entity_file} is missing "
                    f"lower/upper — both are required",
                    file=sys.stderr,
                )
                sys.exit(1)
            if not isinstance(raw_lower, (int, float)) or not math.isfinite(raw_lower):
                print(
                    f"abort: non-finite or non-numeric [estimate] lower in "
                    f"{entity_file} ({raw_lower!r})",
                    file=sys.stderr,
                )
                sys.exit(1)
            if not isinstance(raw_upper, (int, float)) or not math.isfinite(raw_upper):
                print(
                    f"abort: non-finite or non-numeric [estimate] upper in "
                    f"{entity_file} ({raw_upper!r})",
                    file=sys.stderr,
                )
                sys.exit(1)
            if float(raw_lower) < 0.0:
                print(
                    f"abort: [estimate] lower < 0 in {entity_file} "
                    f"({raw_lower!r})",
                    file=sys.stderr,
                )
                sys.exit(1)
            if float(raw_upper) < float(raw_lower):
                print(
                    f"abort: [estimate] upper < lower in {entity_file} "
                    f"({raw_lower!r} > {raw_upper!r})",
                    file=sys.stderr,
                )
                sys.exit(1)
            relpath = entity_file.relative_to(root).as_posix()
            facets.append(
                Facet(
                    relpath=relpath,
                    abs_path=entity_file,
                    canonical_id=f"{prefix}-{child.name}",
                    lower=float(raw_lower),
                    upper=float(raw_upper),
                )
            )
    return facets


# ---------------------------------------------------------------------------
# [estimate] table line-span location (shared by basis-citation and strip)
# ---------------------------------------------------------------------------


def locate_estimate_table(lines: list[str]) -> tuple[int, int] | None:
    """Returns (header_idx, end_idx) 0-based, `end_idx` exclusive, or None
    if no top-level `[estimate]` header is present.
    """
    header_idx = None
    for i, line in enumerate(lines):
        if ESTIMATE_HEADER_RE.match(line.rstrip("\n")):
            header_idx = i
            break
    if header_idx is None:
        return None
    end_idx = len(lines)
    for j in range(header_idx + 1, len(lines)):
        if SECTION_HEADER_RE.match(lines[j]):
            end_idx = j
            break
    return (header_idx, end_idx)


def git_basis(root: Path, relpath: str, run_date: str) -> str:
    """`basis = "facet [estimate] <relpath> @ <commit> <author> <date>"` from
    `git blame` of the `lower =` line — best-effort; on failure, the basis
    carries the path only (recovered context, never asserted provenance).
    """
    fallback = f"facet [estimate] {relpath}"
    abs_path = root / relpath
    try:
        text = abs_path.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        loc = locate_estimate_table(lines)
        if loc is None:
            return fallback
        # Find the lower= line within the estimate table span
        lower_line_no = None
        for j in range(loc[0] + 1, loc[1]):
            if ESTIMATE_LOWER_RE.match(lines[j]):
                lower_line_no = j + 1  # 1-based for git blame -L
                break
        if lower_line_no is None:
            return fallback
        result = subprocess.run(
            ["git", "blame", "--line-porcelain", "-L", f"{lower_line_no},{lower_line_no}", "--", relpath],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
        blame_lines = result.stdout.splitlines()
        if not blame_lines:
            return fallback
        sha = blame_lines[0].split()[0][:8]
        author = None
        author_time = None
        for bl in blame_lines:
            if bl.startswith("author "):
                author = bl[len("author ") :]
            elif bl.startswith("author-time "):
                author_time = int(bl[len("author-time ") :])
        if author is None or author_time is None:
            return fallback
        blame_date = datetime.fromtimestamp(author_time, tz=timezone.utc).strftime("%Y-%m-%d")
        return f"facet [estimate] {relpath} @ {sha} {author} {blame_date}"
    except Exception:
        return fallback


# ---------------------------------------------------------------------------
# Stage 4 (pre-compute): classify against the existing migrated corpus
# ---------------------------------------------------------------------------


@dataclass
class ActiveMigratedRow:
    uid: str
    lower: float
    upper: float
    session_file: Path


def load_active_migrated_rows(root: Path) -> dict[str, ActiveMigratedRow]:
    """source relpath -> the single active `rater = migrated` row citing it.

    "Active" here means: not the target of another row's `supersedes`, and
    not tombstoned. This script is the sole writer of `rater = migrated`
    rows, and always supersedes explicitly (never mutates in place), so at
    most one active row per source path is expected; more than one is an
    integrity violation this script refuses to silently resolve.
    """
    comparisons_dir = root / COMPARISONS_DIR
    if not comparisons_dir.is_dir():
        return {}

    all_rows: list[dict] = []
    tombstoned: set[str] = set()
    for session_file in sorted(comparisons_dir.glob("*.toml")):
        with open(session_file, "rb") as fh:
            doc = tomllib.load(fh)
        for row in doc.get("judgement", []):
            row = dict(row)
            row["_session_file"] = session_file
            all_rows.append(row)
        for tomb in doc.get("tombstone", []):
            target = tomb.get("target")
            if target:
                tombstoned.add(target)

    superseded = {row["supersedes"] for row in all_rows if row.get("supersedes")}

    by_source: dict[str, list[dict]] = {}
    for row in all_rows:
        if row.get("rater") != "migrated":
            continue
        if row.get("uid") in superseded or row.get("uid") in tombstoned:
            continue
        basis = row.get("basis", "")
        m = BASIS_SOURCE_RE.match(basis)
        if not m:
            continue
        source_path = m.group(1)
        by_source.setdefault(source_path, []).append(row)

    active: dict[str, ActiveMigratedRow] = {}
    for source_path, rows in by_source.items():
        if len(rows) > 1:
            uids = ", ".join(r["uid"] for r in rows)
            print(
                f"abort: integrity violation — {len(rows)} active migrated rows "
                f"cite the same source {source_path} (uids: {uids}); manual "
                "reconciliation required before this script can proceed",
                file=sys.stderr,
            )
            sys.exit(1)
        row = rows[0]
        active[source_path] = ActiveMigratedRow(
            uid=row["uid"],
            lower=float(row.get("est_lower", math.nan)),
            upper=float(row.get("est_upper", math.nan)),
            session_file=row["_session_file"],
        )
    return active


@dataclass
class Classified:
    facet: Facet
    category: str  # "imported" | "already-imported" | "re-imported"
    supersedes_uid: str | None


def classify(facets: list[Facet], active_by_source: dict[str, ActiveMigratedRow]) -> list[Classified]:
    out = []
    for f in facets:
        active = active_by_source.get(f.relpath)
        if active is None:
            out.append(Classified(f, "imported", None))
        elif active.lower == f.lower and active.upper == f.upper:
            out.append(Classified(f, "already-imported", None))
        else:
            out.append(Classified(f, "re-imported", active.uid))
    return out


# ---------------------------------------------------------------------------
# Stage 2: emit
# ---------------------------------------------------------------------------


def toml_quote(s: str) -> str:
    out = s.replace("\\", "\\\\").replace('"', '\\"')
    out = out.replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return f'"{out}"'


def render_session(rows_to_emit: list[Classified], root: Path, run_date: str) -> tuple[str, str]:
    """Returns (filename, text) for the session-per-run file (RV-278 F-7)."""
    session_uid = str(uuid.uuid4())
    lines = [
        'schema = "doctrine.comparison-session"\n',
        "version = 3\n",
        "tombstone = []\n",
        "\n",
        "[session]\n",
        f"uid = {toml_quote(session_uid)}\n",
        f"date = {toml_quote(run_date)}\n",
        'audience = "migration"\n',
    ]
    for c in rows_to_emit:
        row_uid = str(uuid.uuid4())
        basis = git_basis(root, c.facet.relpath, run_date)
        lines.append("\n")
        lines.append("[[judgement]]\n")
        lines.append(f"uid = {toml_quote(row_uid)}\n")
        lines.append("seq = 0\n")
        lines.append(f"a = {toml_quote(c.facet.canonical_id)}\n")
        lines.append('form = "anchor"\n')
        lines.append('domain = "estimate"\n')
        lines.append('frame = "cost-anchor"\n')
        lines.append(f"est_lower = {c.facet.lower!r}\n")
        lines.append(f"est_upper = {c.facet.upper!r}\n")
        lines.append('rater = "migrated"\n')
        if c.supersedes_uid is not None:
            lines.append(f"supersedes = {toml_quote(c.supersedes_uid)}\n")
        lines.append(f"basis = {toml_quote(basis)}\n")
        lines.append(f"observed_at = {toml_quote(run_date)}\n")
    filename = f"{run_date}-{session_uid}.toml"
    return filename, "".join(lines)


# ---------------------------------------------------------------------------
# Stage 3: verify
# ---------------------------------------------------------------------------


def verify_parses(root: Path) -> bool:
    cmd = [doctrine_bin(), "compare", "list"]
    result = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
    if result.returncode != 0:
        print("parse-gate FAILED — the emitted/corpus comparison sessions do not parse/resolve:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        print(
            "note: the doctrine binary must be a build that supports v3 wire "
            "with `est_lower`/`est_upper`/`cost-anchor` (SL-222 PHASE-06 landed). "
            "Set DOCTRINE_BIN if the on-PATH binary is incompatible.",
            file=sys.stderr,
        )
        return False
    return True


# ---------------------------------------------------------------------------
# Stage 5: strip
# ---------------------------------------------------------------------------


def strip_facet(f: Facet) -> tuple[bool, str]:
    """Returns (ok, message)."""
    text = f.abs_path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    loc = locate_estimate_table(lines)
    if loc is None:
        return False, f"integrity error: [estimate] table vanished from {f.abs_path} between scan and strip"
    header_idx, end_idx = loc
    new_lines = lines[:header_idx] + lines[end_idx:]
    new_text = "".join(new_lines)

    orig_doc = tomllib.loads(text)
    new_doc = tomllib.loads(new_text)
    expected = dict(orig_doc)
    expected.pop("estimate", None)
    if new_doc != expected:
        return (
            False,
            f"strip verification FAILED for {f.abs_path} — post-strip parse != "
            "pre-strip parse minus `estimate`; NOT written. Revert instructions: "
            "inspect with `git diff -- " + f.abs_path.as_posix() + "`; this "
            "file was untouched so no revert is needed for it specifically, "
            "but re-run this script after investigating (the migrated row "
            "already shadows the stale facet per the rung-5 read rule).",
        )
    f.abs_path.write_text(new_text, encoding="utf-8")
    return True, f"stripped {f.abs_path}"


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="stages 1-4: scan, census check ONLY — no emit, no verify, no strip (F-7: truly non-mutating)")
    mode.add_argument("--execute", action="store_true", help="stages 1-5: emit, verify, strip migrated [estimate] tables")
    args = parser.parse_args()

    root = Path.cwd()
    refuse_if_dirty(root)

    if not (root / ".doctrine").is_dir():
        print(f"refusing: no .doctrine/ under {root} — run from a project root", file=sys.stderr)
        sys.exit(1)

    run_date = date.today().isoformat()

    # Stage 1: scan
    facets = scan_facets(root)
    print(f"scan: {len(facets)} [estimate] facet(s) found")
    if not facets:
        print("nothing to migrate")
        return

    active_by_source = load_active_migrated_rows(root)
    classified = classify(facets, active_by_source)

    to_emit = [c for c in classified if c.category != "already-imported"]

    if args.check:
        # F-7: --check is TRULY non-mutating — compute everything in memory,
        # write nothing. Print the census that WOULD happen.
        imported = sum(1 for c in classified if c.category == "imported")
        already = sum(1 for c in classified if c.category == "already-imported")
        reimported = sum(1 for c in classified if c.category == "re-imported")
        print(
            f"census: facets_found={len(classified)} imported={imported} "
            f"already-imported={already} re-imported(superseding)={reimported}"
        )
        for c in classified:
            print(f"  {c.category:<20} {c.facet.canonical_id:<10} {c.facet.relpath}  lower={c.facet.lower} upper={c.facet.upper}")
        if len(classified) != imported + already + reimported:
            print(
                "abort: census does not reconcile "
                f"(facets_found={len(classified)} != imported+already-imported+re-imported="
                f"{imported + already + reimported})",
                file=sys.stderr,
            )
            sys.exit(1)
        print("--check complete (no emit, no verify, no strip — tree unchanged)")
        return

    # --execute path: stages 2-5
    # Stage 2: emit
    if to_emit:
        (root / COMPARISONS_DIR).mkdir(parents=True, exist_ok=True)
        filename, text = render_session(to_emit, root, run_date)
        out_path = root / COMPARISONS_DIR / filename
        out_path.write_text(text, encoding="utf-8")
        print(f"emit: wrote {out_path} ({len(to_emit)} row(s))")
    else:
        print("emit: nothing to import — no session file written")

    # Stage 3: verify (gate before any strip)
    if not verify_parses(root):
        sys.exit(1)
    print("verify: OK — comparison corpus parses/resolves")

    # Stage 4: census
    imported = sum(1 for c in classified if c.category == "imported")
    already = sum(1 for c in classified if c.category == "already-imported")
    reimported = sum(1 for c in classified if c.category == "re-imported")
    print(
        f"census: facets_found={len(classified)} imported={imported} "
        f"already-imported={already} re-imported(superseding)={reimported}"
    )
    for c in classified:
        print(f"  {c.category:<20} {c.facet.canonical_id:<10} {c.facet.relpath}  lower={c.facet.lower} upper={c.facet.upper}")
    if len(classified) != imported + already + reimported:
        print(
            "abort: census does not reconcile "
            f"(facets_found={len(classified)} != imported+already-imported+re-imported="
            f"{imported + already + reimported}) — refusing to strip",
            file=sys.stderr,
        )
        sys.exit(1)

    # Stage 5: strip
    failures = []
    for c in classified:
        ok, message = strip_facet(c.facet)
        print(("strip: OK   " if ok else "strip: FAIL ") + message)
        if not ok:
            failures.append(c.facet.relpath)

    if failures:
        print(
            f"--execute completed with {len(failures)} strip failure(s): {', '.join(failures)} "
            "— those facets remain in place; their migrated row already shadows them "
            "(rung-5 read rule), so a re-run will retry the strip idempotently",
            file=sys.stderr,
        )
        sys.exit(1)
    print("--execute complete: all facets stripped and verified")


if __name__ == "__main__":
    main()
