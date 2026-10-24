#!/usr/bin/env python3
"""Generate an ER-style diagram for SATAN's `mem` operating-memory schema.

Renders docs/diagrams/mem-schema.svg (+ .png). The layout and every label here
are a point-in-time snapshot of the `mem` schema, so they may be stale: after
any migration, update this script and regenerate:

    python3 mem-schema.py && inkscape mem-schema.svg --export-type=png \
        --export-width=2500 --export-filename=mem-schema.png
"""
import html

W, H = 1520, 1540
PAPER = "#f7f3ea"
CARD = "#fffdf7"
INK = "#1c1a17"
MUTED = "#7c766a"
FAINT = "#a9a294"
MONO = "Fira Mono, DejaVu Sans Mono, monospace"
SERIF = "Charter, DejaVu Serif, serif"

EVID = "#a3711b"   # evidence
BELIEF = "#9b3d2c"  # belief
VOCAB = "#5b6068"  # vocabulary
ATT = "#1b6a63"    # attention
NARR = "#63508c"   # narrative

HEAD_H, ROW_H, FOOT_H, PAD_B = 34, 19, 17, 9

out = []


def e(s):
    return html.escape(str(s), quote=True)


class Box:
    def __init__(self, name, rows, footer, x, y, colour, w=340, sub="", tag="table"):
        self.name, self.rows, self.footer = name, rows, footer
        self.x, self.y, self.w, self.colour, self.sub = x, y, w, colour, sub
        self.tag = tag
        self.h = HEAD_H + len(rows) * ROW_H + (len(footer) * FOOT_H + PAD_B + 7 if footer else 0)

    cy = property(lambda s: s.y + s.h / 2)
    cx = property(lambda s: s.x + s.w / 2)
    bottom = property(lambda s: s.y + s.h)
    right = property(lambda s: s.x + s.w)
    foot_top = property(lambda s: s.y + HEAD_H + len(s.rows) * ROW_H)

    def rowy(self, i):
        return self.y + HEAD_H + i * ROW_H + ROW_H / 2

    def svg(self):
        c, x, y, w, h = self.colour, self.x, self.y, self.w, self.h
        s = [f'<rect x="{x + 3}" y="{y + 3}" width="{w}" height="{h}" rx="3" fill="{INK}" opacity="0.06"/>',
             f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="{CARD}" stroke="{INK}" stroke-width="1.1"/>',
             f'<path d="M{x} {y + HEAD_H} V{y + 3} a3 3 0 0 1 3 -3 H{self.right - 3} a3 3 0 0 1 3 3 '
             f'V{y + HEAD_H} Z" fill="{c}" opacity="0.13"/>',
             f'<line x1="{x}" y1="{y + HEAD_H}" x2="{self.right}" y2="{y + HEAD_H}" stroke="{c}" stroke-width="1.1"/>',
             f'<path d="M{x + 0.6} {y + 12} V{self.bottom - 12}" stroke="{c}" stroke-width="3.4" stroke-linecap="round"/>',
             f'<text x="{x + 16}" y="{y + 22}" class="tname" fill="{INK}">{e(self.name)}</text>']
        if self.sub:
            s.append(f'<text x="{self.right - 16}" y="{y + 22}" class="tsub" fill="{c}" '
                     f'text-anchor="end">{e(self.sub)}</text>')
        for i, (nm, ty, key) in enumerate(self.rows):
            ry = self.rowy(i)
            s.append(f'<text x="{x + 16}" y="{ry}" class="col" fill="{INK}">{e(nm)}</text>')
            if key:
                s.append(f'<text x="{self.right - 16}" y="{ry}" class="key" fill="{c}" '
                         f'text-anchor="end">{e(key)}</text>')
            s.append(f'<text x="{self.right - 42}" y="{ry}" class="type" fill="{MUTED}" '
                     f'text-anchor="end">{e(ty)}</text>')
        if self.footer:
            ft = self.foot_top
            s.append(f'<line x1="{x + 10}" y1="{ft + 3}" x2="{self.right - 10}" y2="{ft + 3}" '
                     f'stroke="{c}" stroke-width="0.8" stroke-dasharray="2 3" opacity="0.8"/>')
            for j, line in enumerate(self.footer):
                s.append(f'<text x="{x + 16}" y="{ft + 18 + j * FOOT_H}" class="foot" '
                         f'fill="{MUTED}">{e(line)}</text>')
        return "\n".join(s)


def poly(points, colour, dashed=False, width=1.35, arrow=False):
    r = 9.0
    d = [f"M{points[0][0]} {points[0][1]}"]
    for i in range(1, len(points) - 1):
        x0, y0 = points[i - 1]
        x1, y1 = points[i]
        x2, y2 = points[i + 1]

        def shrink(a, b):
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = (dx * dx + dy * dy) ** 0.5 or 1
            k = min(r, ln / 2) / ln
            return (a[0] + dx * k, a[1] + dy * k)

        p, q = shrink((x1, y1), (x0, y0)), shrink((x1, y1), (x2, y2))
        d.append(f"L{p[0]:.1f} {p[1]:.1f}")
        d.append(f"Q{x1} {y1} {q[0]:.1f} {q[1]:.1f}")
    d.append(f"L{points[-1][0]} {points[-1][1]}")
    da = ' stroke-dasharray="5 5"' if dashed else ""
    mk = ' marker-end="url(#arrow)"' if arrow else ""
    return (f'<path d="{" ".join(d)}" fill="none" stroke="{colour}" stroke-width="{width}" '
            f'stroke-linecap="round"{da}{mk}/>')


def bow(x_edge, y0, y1, x_apex, colour):
    """Self-association bracket: out from x_edge, across to x_apex, back in."""
    return (f'<path d="M{x_edge} {y0} L{x_apex - 8} {y0} Q{x_apex} {y0} {x_apex} {y0 + 8} '
            f'L{x_apex} {y1 - 8} Q{x_apex} {y1} {x_apex - 8} {y1} L{x_edge} {y1}" fill="none" '
            f'stroke="{colour}" stroke-width="1.35" stroke-linecap="round"/>')


def foot(x, y, direction, colour):
    """Crow's-foot 'many' marker, prongs touching the box edge at (x, y)."""
    if direction in ("left", "right"):
        jx = x + (-15 if direction == "left" else 15)
        path = f"M{jx} {y} L{x} {y - 8} M{jx} {y} L{x} {y} M{jx} {y} L{x} {y + 8}"
    else:
        jy = y + (-15 if direction == "up" else 15)
        path = f"M{x} {jy} L{x - 8} {y} M{x} {jy} L{x} {y} M{x} {jy} L{x + 8} {y}"
    return f'<path d="{path}" stroke="{colour}" stroke-width="1.35" fill="none" stroke-linecap="round"/>'


def one(x, y, direction, colour):
    """IE 'exactly one' marker: a tick across the line, set off the box edge."""
    if direction in ("left", "right"):
        x += 9 if direction == "right" else -9
        return f'<line x1="{x}" y1="{y - 7}" x2="{x}" y2="{y + 7}" stroke="{colour}" stroke-width="1.7"/>'
    y += 9 if direction == "down" else -9
    return f'<line x1="{x - 7}" y1="{y}" x2="{x + 7}" y2="{y}" stroke="{colour}" stroke-width="1.7"/>'


def chip(x, y, label, colour, sub="", anchor="middle", side="above"):
    """Paper-backed label on a connector. `sub` carries the ON DELETE action."""
    wd = max(len(label) * 6.05, len(sub) * 5.85) + 14
    if anchor == "middle":
        x -= wd / 2
    elif anchor == "end":
        x -= wd
    hgt = 26 if sub else 16
    if side == "above":
        ry, base = y - hgt - 4, (y - 19 if sub else y - 8)
    elif side == "below":
        ry, base = y + 5, (y + 14 if sub else y + 25 - 5)
    else:
        ry, base = y - hgt / 2, (y - 1 if sub else y + 4)
        x = x + 6 if side == "right" else x - wd - 6
    s = [f'<rect x="{x:.0f}" y="{ry:.0f}" width="{wd:.0f}" height="{hgt}" rx="2" fill="{PAPER}" opacity="0.95"/>',
         f'<text x="{x + 7:.0f}" y="{base}" class="chip" fill="{colour}">{e(label)}</text>']
    if sub:
        s.append(f'<text x="{x + 7:.0f}" y="{base + 10}" class="chips" fill="{FAINT}">{e(sub)}</text>')
    return "\n".join(s)


def wrap(text, budget):
    lines, cur = [], ""
    for word in text.split():
        cand = (cur + " " + word).strip()
        if len(cand) > budget and cur:
            lines.append(cur)
            cur = word
        else:
            cur = cand
    if cur:
        lines.append(cur)
    return lines


def note(x, y, label, body, budget=54):
    s = [f'<line x1="{x}" y1="{y - 13}" x2="{x + 26}" y2="{y - 13}" stroke="{MUTED}" stroke-width="1.6"/>',
         f'<text x="{x}" y="{y + 2}" class="notelabel" fill="{INK}">{e(label)}</text>']
    yy = y + 23
    for line in wrap(body, budget):
        s.append(f'<text x="{x}" y="{yy}" class="notebody" fill="{MUTED}">{e(line)}</text>')
        yy += 16
    return "\n".join(s)


# ------------------------------------------------------------------ layout ---
source = Box("mem.source", [
    ("id", "bigserial", "PK"),
    ("ref", "text", ""),
    ("detail", "text", ""),
    ("modality", "text", ""),
    ("epistemic", "text", ""),
    ("authority", "text", ""),
    ("seen_at", "timestamptz", ""),
    ("last_seen_at", "timestamptz", ""),
], [
    "modality : file · commit · conversation · web",
    "epistemic: observation · inference · spec · testimony",
    "authority: user · agent · upstream · third_party",
    "unique (modality, ref, detail)",
], 80, 450, EVID, w=360, sub="what I saw")

claim_source = Box("mem.claim_source", [
    ("claim_id", "bigint", "FK"),
    ("source_id", "bigint", "FK"),
    ("relation", "text", ""),
], [
    "relation ∈ supports · contradicts · derived_from",
    "PK (claim_id, source_id, relation)",
    "claim cascade · source restrict",
], 500, 450, BELIEF, w=310, sub="the receipt")

claim = Box("mem.claim", [
    ("id", "bigserial", "PK"),
    ("subject", "text", "FK"),
    ("predicate", "text", "FK"),
    ("object", "text", ""),
    ("confidence", "numeric", ""),
    ("status", "text", ""),
    ("asserted_at", "timestamptz", ""),
    ("valid_from", "timestamptz", ""),
    ("valid_to", "timestamptz", ""),
    ("note", "text", ""),
    ("superseded_by", "bigint", "FK"),
    ("search_text", "text", "GEN"),
    ("retired_at", "timestamptz", ""),
], [
    "status ∈ held · confirmed · refuted · stale · superseded",
    "held/confirmed ⇔ retired_at NULL · idx (superseded_by)",
    "one live triple: unique (subject, predicate, object)",
    "object: NULL == '' for the live-triple index",
    "  where retired_at IS NULL · gin trgm (search_text)",
], 880, 392, BELIEF, w=380, sub="what I hold")

subject = Box("mem.subject", [
    ("slug", "", "PK"),
    ("title", "", ""),
    ("domain", "", "GEN"),
], [], 880, 236, VOCAB, w=200, sub="vocab")

predicate = Box("mem.predicate", [
    ("slug", "", "PK"),
    ("scope", "", ""),
    ("defn", "", ""),
    ("created_at", "", ""),
], [], 1110, 236, VOCAB, w=200, sub="vocab")

intent = Box("mem.intent", [
    ("id", "bigserial", "PK"),
    ("slug", "text", "UQ"),
    ("title", "text", ""),
    ("status", "text", ""),
    ("waiting_for", "text", ""),
    ("next_step", "text", ""),
    ("plan", "text", ""),
    ("created_at", "timestamptz", ""),
    ("updated_at", "timestamptz", ""),
    ("closed_at", "timestamptz", ""),
], [
    "status ∈ active · blocked · done · abandoned",
    "done/abandoned ⇔ closed_at NOT NULL",
    "idx (updated_at desc) where active/blocked",
], 80, 860, ATT, w=340, sub="what I'm doing")

journal = Box("mem.journal", [
    ("id", "bigserial", "PK"),
    ("at", "timestamptz", ""),
    ("intent_id", "bigint", "FK"),
    ("kind", "text", ""),
    ("body", "text", ""),
    ("source_id", "bigint", "FK"),
    ("claim_id", "bigint", "FK"),
    ("created_by", "text", ""),
], [
    "kind ∈ action · finding · error · decision ·",
    "     question · wakeup · sleep",
    "decision ⇒ a claim or an intent · append-only",
], 500, 860, ATT, w=340, sub="what came of it")

hip = Box("mem.hippocampus_ref", [
    ("id", "bigserial", "PK"),
    ("claim_id", "bigint", "FK"),
    ("intent_id", "bigint", "FK"),
    ("filename", "text", ""),
], [
    "check: exactly one of claim_id, intent_id",
    "unique (filename, claim_id) · (filename, intent_id)",
    "narrative memory · git-versioned prose",
], 880, 1150, NARR, w=380, sub="the hinge")

claim_source.y = source.cy - claim_source.h / 2

FR_X0, FR_X1 = claim.x - 12, claim.right + 12
FR_Y0, FR_Y1 = claim.y - 12, claim.bottom + 12

HIP_W, HIP_H = 380, 64
hipbox_x, hipbox_y = hip.cx - HIP_W / 2, 1380

# ---------------------------------------------------------------- assembly ---
out.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">')
out.append(f"""<defs>
<style>
  .tname {{ font-family: {MONO}; font-size: 13.5px; font-weight: 600; letter-spacing: .2px; }}
  .tsub  {{ font-family: {MONO}; font-size: 9.5px; letter-spacing: .9px; text-transform: uppercase; }}
  .col   {{ font-family: {MONO}; font-size: 12.2px; }}
  .type  {{ font-family: {MONO}; font-size: 10.6px; }}
  .key   {{ font-family: {MONO}; font-size: 9px; letter-spacing: .7px; }}
  .foot  {{ font-family: {MONO}; font-size: 9.4px; }}
  .chip  {{ font-family: {MONO}; font-size: 10px; }}
  .chips {{ font-family: {MONO}; font-size: 8.6px; letter-spacing: .3px; }}
  .notelabel {{ font-family: {MONO}; font-size: 9.6px; letter-spacing: 1.5px; text-transform: uppercase; }}
  .notebody  {{ font-family: {SERIF}; font-size: 12.4px; }}
  .eyebrow {{ font-family: {MONO}; font-size: 10.5px; letter-spacing: 2.4px; text-transform: uppercase; }}
  .title {{ font-family: {SERIF}; font-size: 42px; letter-spacing: -.6px; }}
  .subtitle {{ font-family: {SERIF}; font-size: 17px; font-style: italic; }}
  .principle {{ font-family: {MONO}; font-size: 11px; letter-spacing: .4px; }}
  .legend {{ font-family: {SERIF}; font-size: 12.2px; }}
  .legendname {{ font-family: {MONO}; font-size: 10px; letter-spacing: 1.7px; text-transform: uppercase; }}
  .rule {{ font-family: {MONO}; font-size: 9.5px; letter-spacing: 2.8px; text-transform: uppercase; }}
  .framelabel {{ font-family: {MONO}; font-size: 10px; letter-spacing: .6px; }}
</style>
<pattern id="dots" width="26" height="26" patternUnits="userSpaceOnUse">
  <circle cx="1" cy="1" r="0.9" fill="{INK}" opacity="0.10"/>
</pattern>
<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7"
        orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="{NARR}"/></marker>
</defs>""")

out.append(f'<rect width="{W}" height="{H}" fill="{PAPER}"/>')
out.append(f'<rect width="{W}" height="{H}" fill="url(#dots)"/>')

# ---- title block
out.append(f'<text x="80" y="70" class="eyebrow" fill="{FAINT}">001-init.sql · schema mem · postgres 18</text>')
out.append(f'<text x="{W - 80}" y="70" class="rule" fill="{FAINT}" text-anchor="end">'
           f'eight tables · one view · one write function</text>')
out.append(f'<text x="80" y="118" class="title" fill="{INK}">Two organs of a memory</text>')
out.append(f'<text x="80" y="150" class="subtitle" fill="{MUTED}">'
           f'What I hold, what I am doing, and the words I am allowed to say it in.</text>')
out.append(f'<text x="80" y="176" class="principle" fill="{BELIEF}">'
           f'provenance is mandatory: nothing asserts knowledge without a source</text>')
out.append(f'<line x1="80" y1="196" x2="{W - 80}" y2="196" stroke="{INK}" stroke-width="0.7" opacity="0.25"/>')

# ---- the read surface: a frame around claim
out.append(f'<rect x="{FR_X0}" y="{FR_Y0}" width="{FR_X1 - FR_X0}" height="{FR_Y1 - FR_Y0}" rx="6" '
           f'fill="{BELIEF}" opacity="0.04"/>')
out.append(f'<rect x="{FR_X0}" y="{FR_Y0}" width="{FR_X1 - FR_X0}" height="{FR_Y1 - FR_Y0}" rx="6" '
           f'fill="none" stroke="{BELIEF}" stroke-width="1" stroke-dasharray="7 6" opacity="0.75"/>')
out.append(f'<text x="{FR_X1 + 14}" y="{FR_Y0 - 20}" class="framelabel" fill="{BELIEF}">mem.asserted</text>')
for k, line in enumerate(["the read surface:", "retired_at IS NULL", "∧ some source supports it",
                          "+ two citation counts"]):
    out.append(f'<text x="{FR_X1 + 14}" y="{FR_Y0 - 6 + k * 12}" class="chips" fill="{MUTED}">{e(line)}</text>')

# ---- connectors (under the boxes)
E = []
# subject / predicate -> claim
for card, col, x_drop in ((subject, "subject", 960), (predicate, "predicate", 1200)):
    E.append(poly([(x_drop, card.bottom), (x_drop, claim.y)], INK))
    E.append(foot(x_drop, claim.y, "up", INK))
    E.append(one(x_drop, card.bottom, "down", INK))
    E.append(chip(x_drop, (card.bottom + claim.y) / 2 + 2, col, VOCAB, side="right"))
# claim_source -> source
E.append(poly([(claim_source.x, claim_source.cy), (source.right, claim_source.cy)], INK))
E.append(foot(claim_source.x, claim_source.cy, "left", INK))
E.append(one(source.right, claim_source.cy, "right", INK))
E.append(chip((source.right + claim_source.x) / 2, claim_source.cy, "source_id", BELIEF))
# claim_source -> claim
E.append(poly([(claim_source.right, claim_source.cy), (claim.x, claim_source.cy)], INK))
E.append(foot(claim_source.right, claim_source.cy, "right", INK))
E.append(one(claim.x, claim_source.cy, "left", INK))
E.append(chip((claim_source.right + claim.x) / 2, claim_source.cy, "claim_id", BELIEF))
# claim.superseded_by -> claim.id  (the only self-reference)
y_sup, y_id = claim.rowy(10), claim.rowy(0)
E.append(bow(claim.right, y_sup, y_id, 1316, BELIEF))
E.append(foot(claim.right, y_sup, "right", BELIEF))
E.append(one(claim.right, y_id, "left", BELIEF))
E.append(chip(1322, (y_sup + y_id) / 2 + 8, "superseded_by", BELIEF, sub="the successor", anchor="start"))
# journal -> intent
jy = journal.rowy(2)
iy = intent.rowy(0)
E.append(poly([(journal.x, jy), (460, jy), (460, iy), (intent.right, iy)], INK))
E.append(foot(journal.x, jy, "left", INK))
E.append(one(intent.right, iy, "right", INK))
E.append(chip(460, (jy + iy) / 2, "intent_id", ATT, sub="set null"))
# journal -> source
sy = journal.rowy(5)
E.append(poly([(journal.x, sy), (480, sy), (480, 762), (400, 762), (400, source.bottom)], INK))
E.append(foot(journal.x, sy, "left", INK))
E.append(one(400, source.bottom, "down", INK))
E.append(chip(440, 762, "source_id", ATT, sub="set null"))
# journal -> claim
cy_ = journal.rowy(6)
E.append(poly([(700, journal.y), (700, 790), (940, 790), (940, claim.bottom)], INK))
E.append(foot(700, journal.y, "up", INK))
E.append(one(940, claim.bottom, "down", INK))
E.append(chip(770, 790, "claim_id", ATT, sub="set null", side="below"))
# hip -> claim  (out right, up, back into claim's bottom)
hy = hip.rowy(1)
E.append(poly([(hip.right, hy), (1316, hy), (1316, 802), (1180, 802), (1180, claim.bottom)], INK))
E.append(foot(hip.right, hy, "right", INK))
E.append(one(1180, claim.bottom, "down", INK))
E.append(chip(1316, (hy + 802) / 2, "claim_id", NARR, sub="restrict", side="left"))
# hip -> intent  (down under the journal, then left)
hy2 = hip.rowy(2)
E.append(poly([(hip.x, hy2), (862, hy2), (862, 1180), (380, 1180), (380, intent.bottom)], INK))
E.append(foot(hip.x, hy2, "left", INK))
E.append(one(380, intent.bottom, "down", INK))
E.append(chip(620, 1180, "intent_id", NARR, sub="restrict"))
# hip.filename -> hippocampus
E.append(poly([(hip.cx, hip.bottom), (hip.cx, hipbox_y)], NARR, dashed=True, arrow=True))
E.append(chip(hip.cx, (hip.bottom + hipbox_y) / 2, "filename", NARR, sub="one file, n rows", side="right"))
out.extend(E)

for b in (source, claim, claim_source, subject, predicate, intent, journal, hip):
    out.append(b.svg())

# ---- narrative target (prose, not rows)
out.append(f'<rect x="{hipbox_x}" y="{hipbox_y}" width="{HIP_W}" height="{HIP_H}" rx="3" '
           f'fill="{NARR}" opacity="0.07"/>')
out.append(f'<rect x="{hipbox_x}" y="{hipbox_y}" width="{HIP_W}" height="{HIP_H}" rx="3" fill="none" '
           f'stroke="{NARR}" stroke-width="1.1" stroke-dasharray="6 5"/>')
out.append(f'<text x="{hip.cx}" y="{hipbox_y + 28}" class="tname" fill="{NARR}" text-anchor="middle">'
           f'hippocampus/&lt;file&gt;.md</text>')
out.append(f'<text x="{hip.cx}" y="{hipbox_y + 48}" class="foot" fill="{MUTED}" text-anchor="middle">'
           f'git-versioned prose · the hinge only points at it</text>')

# ---- notes
out.append(note(80, 250, "the words are registered",
                "A subject and a predicate must exist before a claim can name them. mem.assert_claim() does "
                "the registration, the claim, the citation and the receipt in one transaction."))
out.append(note(80, 358, "contradiction is citable",
                "A citation carries its relation, so evidence against a belief is stored the same way as "
                "evidence for it: a claim can hold its own counter-source."))
out.append(note(500, 1215, "retired, not overwritten",
                "A belief leaves the live set by gaining retired_at. It keeps its row, keeps its citations, "
                "and names its successor; the chain is walked, never inferred."))
out.append(note(500, 1325, "acts are append-only",
                "The journal has no retired_at and no update path. Beliefs may be revised; the doing of them "
                "may not."))

# ---- legend
ly = 1200
out.append(f'<text x="80" y="{ly}" class="rule" fill="{INK}" letter-spacing="2.6">legend</text>')
ly += 16
for col, name, desc in [
    (EVID, "what I saw", "one row per citation, not per document"),
    (BELIEF, "what I hold", "reached through claim_source, read through the view"),
    (VOCAB, "the words allowed", "subject + predicate must be registered first"),
    (ATT, "what I'm doing", "one live thread, with its journal of acts"),
    (NARR, "where the prose lives", "the hinge into hippocampus; it points, never copies"),
]:
    out.append(f'<rect x="80" y="{ly + 4}" width="16" height="16" rx="2" fill="{col}" opacity="0.16"/>')
    out.append(f'<rect x="80" y="{ly + 4}" width="16" height="16" rx="2" fill="none" stroke="{col}" '
               f'stroke-width="1.2"/>')
    out.append(f'<line x1="80" y1="{ly + 12}" x2="96" y2="{ly + 12}" stroke="{col}" stroke-width="3"/>')
    out.append(f'<text x="108" y="{ly + 10}" class="legendname" fill="{col}">{e(name)}</text>')
    out.append(f'<text x="108" y="{ly + 26}" class="legend" fill="{MUTED}">{e(desc)}</text>')
    ly += 42

out.append(f'<line x1="80" y1="{H - 44}" x2="{W - 80}" y2="{H - 44}" stroke="{INK}" stroke-width="0.7" opacity="0.22"/>')
out.append(f'<text x="80" y="{H - 22}" class="foot" fill="{FAINT}">'
           f'crow\'s foot = many · tick = exactly one · sub-label = on delete action · '
           f'GEN = generated · dashed = filename, not a foreign key</text>')
out.append(f'<text x="{W - 80}" y="{H - 22}" class="foot" fill="{FAINT}" text-anchor="end">'
           f'owned by user satan · database satan</text>')
out.append("</svg>")

open("/home/david/dev/satan/docs/diagrams/mem-schema.svg", "w", encoding="utf-8").write("\n".join(out))
print("ok")
