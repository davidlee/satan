`rg --max-columns N` prints the **first N columns of the line**, not the part
around the match. `--max-columns-preview` changes only the replacement: without
it rg prints the literal `[Omitted long matching line]`; with it, the truncated
line plus `[... omitted end of long line]`. Verified against rg on the host:

    line = 400 x, then NEEDLE, then 400 y
    rg --max-columns 200 --max-columns-preview -- NEEDLE FILE
    -> 200 columns of x + [... omitted end of long line]      (no NEEDLE)

With the same query at column ~92 the phrase is present. So the preview flag is
*not* a guarantee that the match is visible; the omission marker is the only
guarantee that the line continues.

Consequence for a grep tool that returns the matched line as `:text`: the text
may not contain the query, while `:path` and `:line` still identify the hit and
remain followable with a read tool. Do not write a description that promises the
phrase. Caught by the SL-020 audit (RV-020 F-2) after the design (RV-019) had
asserted the stronger claim.
