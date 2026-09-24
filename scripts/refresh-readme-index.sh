#!/usr/bin/env bash
set -euo pipefail

# Regenerates the <!-- BEGIN:readme-index --> … <!-- END:readme-index -->
# section of README.md from the committed spec corpus.
#
# Source of truth: the authored spec TOML/MD under .doctrine/spec/<subtype>/
# (the committed, reviewed tier of doctrine's storage model — not runtime state).
#
# Subtypes: Product Specifications (PRD-*), Technical Specifications (SPEC-*),
# Request for Comments (RFC-*), Architecture Decision Records (ADR-*).

README="README.md"
SPEC_ROOT=".doctrine/spec"

if ! grep -q 'BEGIN:readme-index' "$README"; then
  echo "error: no <!-- BEGIN:readme-index --> marker in $README" >&2
  exit 1
fi

# Pull a scalar string field (title = "…") out of an authored spec/slice TOML.
toml_str() { grep -m1 "^$2 = " "$1" | sed "s/^$2 = \"\(.*\)\"/\1/"; }

# Phase rollups (N/M, —, !N, ?N) are CLI-derived from the gitignored state tree
# — `slice list` is the only source. Map id -> rollup token; — when unavailable.
declare -A ROLLUP
if command -v doctrine >/dev/null 2>&1; then
  while read -r _id _roll; do ROLLUP["$_id"]="$_roll"; done < <(
    doctrine slice list 2>/dev/null | awk 'NR>1 {
      roll="—"
      for (i=2;i<=NF;i++) if ($i ~ /^(—|[0-9]+\/[0-9]+|[!?][0-9]+)$/) { roll=$i; break }
      print $1, roll
    }' || true
  )
fi

section=""

# Append one authored-entity block. $1 = dir, $2 = id prefix, $3 = heading,
# $4 = file stem (spec|adr). title + status live in `<stem>-NNN.toml`.
# Iterates the `NNN-slug` symlinks so id, slug, and link path come from one name.
add_subtype() {
  local subdir="$1" prefix="$2" heading="$3" stem="$4"
  local sym base id md toml title status block=""
  [[ -d "$subdir" ]] || return 0
  # Real NNN dirs only — GitHub does not traverse the NNN-slug symlinks (404).
  for sym in $(find "$subdir" -maxdepth 1 -type d -name '[0-9]*' | sort); do
    base="$(basename "$sym")"
    id="${base%%-*}"
    md="$sym/$stem-$id.md"
    toml="$sym/$stem-$id.toml"
    [[ -f "$md" && -f "$toml" ]] || continue
    title="$(toml_str "$toml" title)"
    status="$(toml_str "$toml" status)"
    block+="- [$prefix-$id — $title]($md) — \`$status\`\n"
  done
  if [[ -n "$block" ]]; then
    section+="\n### $heading\n\n$block"
  fi
}

add_subtype "$SPEC_ROOT/product" PRD "Product Specifications" spec
add_subtype "$SPEC_ROOT/tech" SPEC "Technical Specifications" spec
add_subtype ".doctrine/rfc" RFC "Request for Comments" rfc
add_subtype ".doctrine/adr" ADR "Architecture Decision Records" adr

# Compact slice index: title -> design, "scope" -> scope doc, (rollup) from CLI.
add_slices() {
  local sym base id title rollup design block=""
  # Real NNN dirs only — GitHub does not traverse the NNN-slug symlinks (404).
  for sym in $(find ".doctrine/slice" -maxdepth 1 -type d -name '[0-9]*' | sort); do
    base="$(basename "$sym")"
    id="${base%%-*}"
    [[ -f "$sym/slice-$id.toml" ]] || continue
    title="$(toml_str "$sym/slice-$id.toml" title)"
    rollup="${ROLLUP[$id]:-—}"
    if [[ -f "$sym/design.md" ]]; then
      design="[$id $title]($sym/design.md)"
    else
      design="$id $title"
    fi
    block+="- $design | [scope]($sym/slice-$id.md) ($rollup)\n"
  done
  if [[ -n "$block" ]]; then
    section+="\n### Slices\n\n$block"
  fi
}

# add_slices

# Drop the leading literal "\n" so the first heading abuts the BEGIN marker.
section="${section#\\n}"

# Replace the marked section. awk -v expands the literal \n escapes.
tmpfile=$(mktemp)
awk -v section="$section" '
  /<!-- BEGIN:readme-index -->/ { print; printf "%s", section; skip=1; next }
  /<!-- END:readme-index -->/   { skip=0 }
  skip { next }
  { print }
' "$README" >"$tmpfile"

mv "$tmpfile" "$README"
echo "readme index refreshed"
