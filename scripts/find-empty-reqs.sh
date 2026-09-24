#!/usr/bin/env bash
# find-empty-reqs.sh — report REQ entities with unfilled prose or TOML fields
# Usage: ./scripts/find-empty-reqs.sh [--brief] [--ids-only]
#
# Template placeholders ({{…}}) = never touched at all → reported separately.
# Empty sections/fields = scaffolded but no substance → reported by category.
set -euo pipefail

MODE=full
for arg; do
  case "$arg" in
    --brief) MODE=brief ;;
    --ids-only) MODE=ids ;;
  esac
done

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for toml in .doctrine/requirement/*/requirement-*.toml; do
  dir=$(dirname "$toml")
  [[ -L "$dir" ]] && continue  # skip slug-symlink dirs
  [[ -f "$toml" ]] || continue
  id=$(basename "$toml" .toml | sed 's/^requirement-//')
  issues=""

  # --- TOML checks ---
  if grep -q '{{id}}\|{{slug}}\|{{title}}' "$toml" 2>/dev/null; then
    issues="$issues TOML-TEMPLATE"
  else
    if grep -q 'acceptance_criteria = \[\]' "$toml" 2>/dev/null; then
      issues="$issues no-acceptance_criteria"
    fi
    if grep -q 'tags = \[\]' "$toml" 2>/dev/null; then
      issues="$issues no-tags"
    fi
  fi

  # --- MD checks ---
  md="${toml%.toml}.md"
  if [[ -f "$md" ]]; then
    if grep -q '{{ref}}\|{{title}}' "$md" 2>/dev/null; then
      issues="$issues MD-TEMPLATE"
    else
      stmt=$(sed -n '/^## Statement/,/^##/p' "$md" 2>/dev/null \
             | grep -v '^##\|<!--.*-->\|^[[:space:]]*$' || true)
      if [[ -z "$stmt" ]]; then issues="$issues no-Statement"; fi

      rat=$(sed -n '/^## Rationale/,$ p' "$md" 2>/dev/null \
            | grep -v '^##\|<!--.*-->\|^[[:space:]]*$' || true)
      if [[ -z "$rat" ]]; then issues="$issues no-Rationale"; fi
    fi
  fi

  issues="${issues# }"  # trim leading space
  printf 'REQ-%s\t%s\n' "$id" "$issues" >> "$TMP"
done

# --- Counting (grep -c exits 1 when 0; suppress via { … || true; } ) ---
total=$(wc -l < "$TMP" || true)
{ n_clean=$(grep -c $'\t$' "$TMP" 2>/dev/null); } || n_clean=0
{ n_tmpl=$(grep -c 'TEMPLATE' "$TMP" 2>/dev/null); } || n_tmpl=0
{ n_stmt=$(grep -c 'no-Statement' "$TMP" 2>/dev/null); } || n_stmt=0
{ n_rat=$(grep -c 'no-Rationale' "$TMP" 2>/dev/null); } || n_rat=0
{ n_ac=$(grep -c 'no-acceptance_criteria' "$TMP" 2>/dev/null); } || n_ac=0
{ n_tags=$(grep -c 'no-tags' "$TMP" 2>/dev/null); } || n_tags=0

case "$MODE" in
  ids)
    sort -t$'\t' -k1 -V "$TMP" | while IFS=$'\t' read -r id issues; do
      echo "$id${issues:+: $issues}"
    done
    ;;
  brief)
    echo "=== REQ fill-status report ==="
    echo "total: $total  fully-filled: $n_clean  template: $n_tmpl  no-Statement: $n_stmt  no-Rationale: $n_rat  no-acceptance_criteria: $n_ac  no-tags: $n_tags"
    echo ""
    sort -t$'\t' -k1 -V "$TMP" | while IFS=$'\t' read -r id issues; do
      [[ -n "$issues" ]] && echo "$id:$issues"
    done
    ;;
  *)
    echo "=== REQ fill-status report ==="
    echo "total: $total"
    echo "  fully filled: $n_clean"
    echo "  template (never touched): $n_tmpl"
    echo "  missing Statement: $n_stmt"
    echo "  missing Rationale: $n_rat"
    echo "  empty acceptance_criteria: $n_ac"
    echo "  empty tags: $n_tags"

    for label in "Template (TOML or MD)" "no-Statement" "no-Rationale" "no-acceptance_criteria" "no-tags"; do
      tag="${label%% *}"
      case "$tag" in
        Template) pat='TEMPLATE' ;;
        *) pat="$tag" ;;
      esac
      { count=$(grep -c "$pat" "$TMP" 2>/dev/null); } || count=0
      [[ "$count" -eq 0 ]] && continue
      echo ""
      echo "--- $label ($count) ---"
      grep "$pat" "$TMP" | sort -t$'\t' -k1 -V | while IFS=$'\t' read -r id _; do
        echo "  $id"
      done
    done

    echo ""
    echo "--- Fully filled ($n_clean) ---"
    grep $'\t$' "$TMP" 2>/dev/null | sort -t$'\t' -k1 -V | while IFS=$'\t' read -r id _; do
      echo "  $id"
    done
    ;;
esac
