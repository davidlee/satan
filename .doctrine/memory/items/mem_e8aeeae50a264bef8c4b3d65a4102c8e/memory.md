# SATAN rg JSON path

# rg --json path field is nested object

## Summary

rg --json wraps path in {:text "..."}; extract with (plist-get (plist-get data :path) :text)

## Context

ripgrep's `--json` output wraps the `path` field as an object: `{"path":{"text":"b2/file.md"}}`.
When parsed with `json-parse-string :object-type 'plist`, this becomes `(:path (:text "b2/file.md"))`.
Using `(plist-get data :path)` returns the plist `(:text "...")`, NOT the string path.
Must use `(plist-get (plist-get data :path) :text)` to get the actual file path string.

Discovered during DE-005 P01 search scope implementation when rg output appeared to find no matches.
