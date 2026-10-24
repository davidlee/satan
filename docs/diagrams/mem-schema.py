#!/usr/bin/env python3
"""Generate an ER-style diagram for SATAN's `mem` operating-memory schema."""
import html

W, H = 1460, 1320
PAPER = "#f7f3ea"
CARD = "#fffdf7"
INK = "#1c1a17"
MUTED = "#7c766a"
FAINT = "#a9a294"
MONO = "Fira Mono, DejaVu Sans Mono, monospace"
SERIF = "Charter, DejaVu Serif, serif"

ORG = {
    "evidence": "#a3711b",
    "belief": "#9b3d2c",
    "attention": "#1b6a63",
    "narrative": "#63508c",
}

HEAD_H = 34
ROW_H = 19
FOOT_H = 17
PAD_B = 9

out = []


def e(s):
    return html.escape(str(s), quote=True)


# ---------------------------------------------------------------- geometry ---
class Box:
    def __init__(self, name, rows, footer, x, y, colour, w=340, sub=""):
        self.name, self.rows, self.footer = name, rows, footer
        self.x, self.y, self.w, self.colour, self.sub = x, y, w, colour, sub
        self.h = HEAD_H + len(rows) * ROW_H + (len(footer) * FOOT_H + PAD_B + 7 if footer else 0)

    cy = property(lambda s: s.y + s.h / 2)
    cx = property(lambda s: s.x + s.w / 2)
    bottom = property(lambda s: s.y + s.h)
    right = property(lambda s: s.x + s.w)
    foot_top = property(lambda s: s.y + HEAD_H + len(s.rows) * ROW_H)

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
            ry = y + HEAD_H + i * ROW_H + 13.5
            s.append(f'<text x="{x + 16}" y="{ry}" class="col" fill="{INK}">{e(nm)}</text>')
            if key:
                s.append(f'<text x="{self.right - 16}" y="{ry}" class="key" fill="{c}" '
                         f'text-anchor="end">{e(key)}</text>')
            s.append(f'<text x="{self.right - 40}" y="{ry}" class="type" fill="{MUTED}" '
                     f'text-anchor="end">{e(ty)}</text>')
        if self.footer:
            ft = self.foot_top
            s.append(f'<line x1="{x + 10}" y1="{ft + 3}" x2="{self.right - 10}" y2="{ft + 3}" '
                     f'stroke="{c}" stroke-width="0.8" stroke-dasharray="2 3" opacity="0.8"/>')
            for j, line in enumerate(self.footer):
                s.append(f'<text x="{x + 16}" y="{ft + 18 + j * FOOT_H}" class="foot" fill="{MUTED}">{e(line)}</text>')
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


def foot(x, y, direction, colour):
    """Crow's-foot 'many' marker, prongs touching the box edge at (x, y)."""
    if direction in ("left", "right"):
        jx = x + (-15 if direction == "left" else 15)
        path = f"M{jx} {y} L{x} {y - 8} M{jx} {y} L{x} {y} M{jx} {y} L{x} {y + 8}"
    else:
        jy = y + (-15 if direction == "up" else 15)
        path = f"M{x} {jy} L{x - 8} {y} M{x} {jy} L{x} {y} M{x} {jy} L{x + 8} {y}"
    return (f'<path d="{path}" stroke="{colour}" stroke-width="1.35" fill="none" stroke-linecap="round"/>')


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
    else:  # right / left, vertically centred
        ry, base = y - hgt / 2, (y - 1 if sub else y + 4)
        if side == "right":
            x = x + 6
        else:
            x = x - wd - 6
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


def note(x, y, label, body, budget=56):
    s = [f'<line x1="{x}" y1="{y - 13}" x2="{x + 26}" y2="{y - 13}" stroke="{MUTED}" stroke-width="1.6"/>',
         f'<text x="{x}" y="{y + 2}" class="notelabel" fill="{INK}">{e(label)}</text>']
    yy = y + 23
    for line in wrap(body, budget):
        s.append(f'<text x="{x}" y="{yy}" class="notebody" fill="{MUTED}">{e(line)}</text>')
        yy += 16
    return "\n".join(s)


# ------------------------------------------------------------------ layout ---
source = Box("mem.source", [
    ("id", "bigserial", "PK"), ("kind", "text", ""), ("ref", "text", ""),
    ("detail", "text", ""), ("seen_at", "timestamptz", ""),
], [
    "kind ∈ file · commit · conversation ·",
    "    observation · inference · user · web · spec",
    "ref = path · sha · conversation id · url · slug",
    "unique (kind, ref, detail)",
], 80, 270, ORG["evidence"], sub="what I saw")

claim = Box("mem.claim", [
    ("id", "bigserial", "PK"), ("subject", "text", ""), ("predicate", "text", ""),
    ("object", "text", ""), ("confidence", "numeric", ""), ("status", "text", ""),
    ("asserted_at", "timestamptz", ""), ("valid_from", "timestamptz", ""),
    ("valid_to", "timestamptz", ""), ("note", "text", ""),
], [
    "status ∈ held · confirmed · refuted · stale",
    "confidence 0.00–1.00 · default 0.50",
    "idx (subject, predicate) where valid_to is null",
    "idx gin trgm (subject ‖ predicate ‖ object)",
    "'repo:doctrine' · 'builds_without_network' · value",
], 940, 270, ORG["belief"], sub="what I hold")

claim_source = Box("mem.claim_source", [
    ("claim_id", "bigint", "FK"), ("source_id", "bigint", "FK"), ("relation", "text", ""),
], [
    "relation ∈ supports · contradicts · derived_from",
    "PK (claim_id, source_id, relation)",
    "claim cascade · source restrict",
], 520, 270, ORG["belief"], sub="the receipt")

intent = Box("mem.intent", [
    ("id", "bigserial", "PK"), ("slug", "text", "UQ"), ("title", "text", ""),
    ("status", "text", ""), ("waiting_for", "text", ""), ("next_step", "text", ""),
    ("plan", "text", ""), ("created_at", "timestamptz", ""),
    ("updated_at", "timestamptz", ""), ("closed_at", "timestamptz", ""),
], [
    "status ∈ active · blocked · done · abandoned",
    "waiting_for = the question I need answered",
    "idx (updated_at desc) where status in (active, blocked)",
], 940, 600, ORG["attention"], sub="what I'm doing")

log = Box("mem.log", [
    ("id", "bigserial", "PK"), ("at", "timestamptz", ""), ("intent_id", "bigint", "FK"),
    ("kind", "text", ""), ("body", "text", ""), ("source_id", "bigint", "FK"),
], [
    "kind ∈ action · finding · error · decision ·",
    "    question · wakeup · sleep",
    "append-only · idx (at desc) · idx (intent_id, at desc)",
], 80, 600, ORG["attention"], sub="what came of it")

hip = Box("mem.hippocampus_ref", [
    ("claim_id", "bigint", "FK"), ("intent_id", "bigint", "FK"), ("filename", "text", "PK"),
], [
    "check (claim_id is not null or intent_id is not null)",
    "a hinge row must hang off a belief or a thread",
], 940, 950, ORG["narrative"], sub="the hinge")

claim_source.y = source.cy - claim_source.h / 2
claim.y = source.cy - claim.h / 2
log.y = intent.cy - log.h / 2

MARGIN_X = 1394
HIP_W, HIP_H = 400, 74
hipbox_y = hip.bottom + 62
hipbox_x = hip.cx - HIP_W / 2

# ---------------------------------------------------------------- assembly ---
out.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">')
out.append(f"""<defs>
<style>
  .tname {{ font-family: {MONO}; font-size: 14px; font-weight: 600; letter-spacing: .3px; }}
  .tsub  {{ font-family: {MONO}; font-size: 9.5px; letter-spacing: .9px; text-transform: uppercase; }}
  .col   {{ font-family: {MONO}; font-size: 12.2px; }}
  .type  {{ font-family: {MONO}; font-size: 10.6px; }}
  .key   {{ font-family: {MONO}; font-size: 9px; letter-spacing: .7px; }}
  .foot  {{ font-family: {MONO}; font-size: 9.6px; }}
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
</style>
<pattern id="dots" width="26" height="26" patternUnits="userSpaceOnUse">
  <circle cx="1" cy="1" r="0.9" fill="{INK}" opacity="0.10"/>
</pattern>
<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7"
        orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="{ORG['narrative']}"/></marker>
</defs>""")

out.append(f'<rect width="{W}" height="{H}" fill="{PAPER}"/>')
out.append(f'<rect width="{W}" height="{H}" fill="url(#dots)"/>')

# ---- title block
out.append(f'<text x="80" y="70" class="eyebrow" fill="{FAINT}">001-init.sql · schema mem · postgres</text>')
out.append(f'<text x="{W - 80}" y="70" class="rule" fill="{FAINT}" text-anchor="end">'
           f'6 tables · one schema · every claim carries a source</text>')
out.append(f'<text x="80" y="118" class="title" fill="{INK}">Two organs of a memory</text>')
out.append(f'<text x="80" y="150" class="subtitle" fill="{MUTED}">'
           f'What I hold, and what I am doing — joined by a hinge into the prose.</text>')
out.append(f'<text x="80" y="176" class="principle" fill="{ORG["belief"]}">'
           f'provenance is mandatory: nothing asserts knowledge without a source</text>')
out.append(f'<line x1="80" y1="194" x2="{W - 80}" y2="194" stroke="{INK}" stroke-width="0.7" opacity="0.25"/>')

# ---- connectors (drawn under the boxes)
cB, cA, cN = ORG["belief"], ORG["attention"], ORG["narrative"]
E = []
# claim_source -> source
E.append(poly([(claim_source.x, claim_source.cy), (source.right, source.cy)], INK))
E.append(foot(claim_source.x, claim_source.cy, "left", INK))
E.append(one(source.right, source.cy, "right", INK))
E.append(chip(470, claim_source.cy, "source_id", cB))
# claim_source -> claim
E.append(poly([(claim_source.right, claim_source.cy), (claim.x, claim.cy)], INK))
E.append(foot(claim_source.right, claim_source.cy, "right", INK))
E.append(one(claim.x, claim.cy, "left", INK))
E.append(chip(894, claim_source.cy, "claim_id", cB))
# log -> source
E.append(poly([(log.cx, log.y), (source.cx, source.bottom)], INK))
E.append(foot(log.cx, log.y, "up", INK))
E.append(one(source.cx, source.bottom, "down", INK))
E.append(chip(log.cx, (source.bottom + log.y) / 2 + 2, "source_id", cA, sub="set null", side="right"))
# log -> intent
E.append(poly([(log.right, log.cy), (intent.x, intent.cy)], INK))
E.append(foot(log.right, log.cy, "right", INK))
E.append(one(intent.x, intent.cy, "left", INK))
E.append(chip((log.right + intent.x) / 2, log.cy, "intent_id", cA, sub="set null"))
# hip -> claim  (around the right margin)
E.append(poly([(claim.right, claim.cy), (MARGIN_X, claim.cy), (MARGIN_X, hip.cy), (hip.right, hip.cy)], INK))
E.append(foot(hip.right, hip.cy, "right", INK))
E.append(one(claim.right, claim.cy, "right", INK))
E.append(chip((claim.right + MARGIN_X) / 2, claim.cy, "claim_id", cN, sub="cascade"))
# hip -> intent
E.append(poly([(intent.cx, intent.bottom), (hip.cx, hip.y)], INK))
E.append(foot(hip.cx, hip.y, "up", INK))
E.append(one(intent.cx, intent.bottom, "down", INK))
E.append(chip(intent.cx, (intent.bottom + hip.y) / 2 + 2, "intent_id", cN, sub="cascade", side="right"))
# hip filename -> hippocampus (no FK, an arrow)
E.append(poly([(hip.cx, hip.bottom), (hip.cx, hipbox_y)], cN, dashed=True, arrow=True))
E.append(chip(hip.cx, (hip.bottom + hipbox_y) / 2, "filename", cN, sub="points, never copies", side="right"))
out.extend(E)

for b in (source, claim, claim_source, intent, log, hip):
    out.append(b.svg())

# ---- narrative target (prose, not rows)
out.append(f'<rect x="{hipbox_x}" y="{hipbox_y}" width="{HIP_W}" height="{HIP_H}" rx="3" '
           f'fill="{cN}" opacity="0.07"/>')
out.append(f'<rect x="{hipbox_x}" y="{hipbox_y}" width="{HIP_W}" height="{HIP_H}" rx="3" fill="none" '
           f'stroke="{cN}" stroke-width="1.1" stroke-dasharray="6 5"/>')
out.append(f'<text x="{hip.cx}" y="{hipbox_y + 30}" class="tname" fill="{cN}" text-anchor="middle">'
           f'hippocampus/&lt;file&gt;.md</text>')
out.append(f'<text x="{hip.cx}" y="{hipbox_y + 52}" class="foot" fill="{MUTED}" text-anchor="middle">'
           f'narrative memory · git-versioned prose, not rows</text>')

# ---- margin notes
out.append(note(520, 500, "contradiction is citable",
                "A citation carries its relation, so evidence that argues against a belief is stored the same "
                "way as evidence for it. A claim can hold its own counter-source without leaving the table."))
out.append(note(520, 800, "superseded, not overwritten",
                "A belief is retired by closing valid_to, never by deleting the row. valid_to is null is the "
                "live set, and the partial index keeps that the cheap query; history survives because nothing "
                "edits the past."))
out.append(note(520, 950, "acts are append-only",
                "mem.log has no valid_to and no update path: the record of what was done only grows. Beliefs "
                "may be revised; the doing of them may not."))

# ---- what it answers
ay = 1082
out.append(f'<line x1="520" y1="{ay - 13}" x2="546" y2="{ay - 13}" stroke="{MUTED}" stroke-width="1.6"/>')
out.append(f'<text x="520" y="{ay + 2}" class="notelabel" fill="{INK}">what it can answer</text>')
ay += 26
for q, path, colour in [
    ("what do I believe, and on what?", "claim ▸ claim_source ▸ source", cB),
    ("what am I doing about it?", "intent ▸ log", cA),
    ("where did I write it down?", "hippocampus_ref ▸ hippocampus/*.md", cN),
]:
    out.append(f'<text x="520" y="{ay}" class="notebody" fill="{MUTED}">{e(q)}</text>')
    out.append(f'<text x="520" y="{ay + 15}" class="chiptrail" fill="{colour}">{e(path)}</text>')
    ay += 38

# ---- legend
ly = 880
out.append(f'<text x="80" y="{ly}" class="rule" fill="{INK}" letter-spacing="2.6">legend</text>')
ly += 16
for org, name, desc in [
    ("evidence", "what I saw", "one row per distinct citation, so citing stays cheap"),
    ("belief", "what I hold", "each claim reaches its sources through claim_source"),
    ("attention", "what I'm doing", "one row per live thread, with the log of its acts"),
    ("narrative", "where the prose lives", "the hinge into hippocampus; it points, never copies"),
]:
    out.append(f'<rect x="80" y="{ly + 4}" width="16" height="16" rx="2" fill="{ORG[org]}" opacity="0.16"/>')
    out.append(f'<rect x="80" y="{ly + 4}" width="16" height="16" rx="2" fill="none" stroke="{ORG[org]}" '
               f'stroke-width="1.2"/>')
    out.append(f'<line x1="80" y1="{ly + 12}" x2="96" y2="{ly + 12}" stroke="{ORG[org]}" stroke-width="3"/>')
    out.append(f'<text x="108" y="{ly + 10}" class="legendname" fill="{ORG[org]}">{e(name)}</text>')
    out.append(f'<text x="108" y="{ly + 26}" class="legend" fill="{MUTED}">{e(desc)}</text>')
    ly += 42

out.append(f'<line x1="80" y1="{H - 48}" x2="{W - 80}" y2="{H - 48}" stroke="{INK}" stroke-width="0.7" opacity="0.22"/>')
out.append(f'<text x="80" y="{H - 26}" class="foot" fill="{FAINT}">'
           f'crow\'s foot = many · tick = exactly one · sub-label = on delete action · '
           f'dashed = filename, not a foreign key</text>')
out.append(f'<text x="{W - 80}" y="{H - 26}" class="foot" fill="{FAINT}" text-anchor="end">'
           f'owned by user satan · database satan</text>')
out.append("</svg>")

open("/tmp/memschema/operating-memory-schema.svg", "w", encoding="utf-8").write("\n".join(out))
print("ok")
