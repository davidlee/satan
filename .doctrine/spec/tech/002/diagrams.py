"""Generate the SATAN system diagrams (diagram-design default skin)."""
import sys

PAPER, INK, MUTED, SOFT, ACCENT, LINK = "#f5f5f5", "#2d3142", "#4f5d75", "#7a8399", "#eb6c36", "#2e5aa8"
MONO, SANS = "'Geist Mono', monospace", "'Geist', sans-serif"

KIND = {  # fill, stroke, dash, tag stroke, tag text
  "focal":    ("rgba(235,108,54,0.08)", ACCENT, None, "rgba(235,108,54,0.50)", ACCENT),
  "backend":  ("#ffffff", INK, None, "rgba(45,49,66,0.40)", INK),
  "store":    ("rgba(45,49,66,0.05)", MUTED, None, "rgba(79,93,117,0.50)", MUTED),
  "external": ("rgba(45,49,66,0.03)", "rgba(45,49,66,0.30)", None, "rgba(45,49,66,0.22)", SOFT),
  "input":    ("rgba(79,93,117,0.10)", SOFT, None, "rgba(122,131,153,0.40)", SOFT),
  "optional": ("rgba(45,49,66,0.02)", "rgba(45,49,66,0.20)", "4,3", "rgba(45,49,66,0.20)", SOFT),
}
STROKE = {  # color, width, dash, marker
  "default": (MUTED, 1.2, None, "arrow"),
  "accent":  (ACCENT, 1.4, None, "arrow-accent"),
  "accent-dashed": (ACCENT, 1.2, "5,4", "arrow-accent"),
  "link":    (LINK, 1.2, None, "arrow-link"),
  "dashed":  (MUTED, 1.0, "4,3", "arrow"),
}


def text_w(s, size=8):
  return round(len(s) * size * 0.68 + 10)


class D:
  def __init__(self):
    self.zones, self.arrows, self.labels, self.nodes, self.legend = [], [], [], [], []

  def zone(self, x, y, w, h, label, boundary=False):
    fill, stroke, dash = (("rgba(235,108,54,0.05)", "rgba(235,108,54,0.50)", ' stroke-dasharray="4,4"')
                          if boundary else ("rgba(45,49,66,0.02)", "rgba(45,49,66,0.10)", ""))
    lw = text_w(label, 7)
    color = ACCENT if boundary else "rgba(45,49,66,0.40)"
    self.zones.append(
      f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="0.8"{dash}/>\n'
      f'<rect x="{x + 12}" y="{y + 4}" width="{lw}" height="12" rx="2" fill="{PAPER}"/>\n'
      f'<text x="{x + 12 + lw / 2}" y="{y + 13}" fill="{color}" font-size="7" font-family="{MONO}" '
      f'text-anchor="middle" letter-spacing="0.14em">{label}</text>')

  def path(self, d, style="default", label=None, at=None, color=None):
    c, w, dash, m = STROKE[style]
    dash = f' stroke-dasharray="{dash}"' if dash else ""
    self.arrows.append(f'<path d="{d}" fill="none" stroke="{c}" stroke-width="{w}"{dash} marker-end="url(#{m})"/>')
    if label:
      self.label(*at, label, color or (c if style != "dashed" else MUTED))

  def label(self, cx, y, text, color=MUTED, anchor="middle"):
    """Mask + text; (cx, y) is the mask's centre-x and top."""
    w = text_w(text)
    x = cx - w / 2 if anchor == "middle" else cx
    self.labels.append(
      f'<rect x="{x}" y="{y}" width="{w}" height="12" rx="2" fill="{PAPER}"/>\n'
      f'<text x="{x + w / 2}" y="{y + 9}" fill="{color}" font-size="8" font-family="{MONO}" '
      f'text-anchor="middle" letter-spacing="0.08em">{text}</text>')

  def node(self, x, y, w, h, kind, tag, name, sub, badge=None):
    fill, stroke, dash, tstroke, tcolor = KIND[kind]
    dash = f' stroke-dasharray="{dash}"' if dash else ""
    tw = text_w(tag, 7) - 2
    cx, cy = x + w / 2, y + h / 2
    s = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{PAPER}"/>\n'
         f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill}" stroke="{stroke}" stroke-width="1"{dash}/>\n'
         f'<rect x="{x + 8}" y="{y + 6}" width="{tw}" height="12" rx="2" fill="transparent" stroke="{tstroke}" stroke-width="0.8"/>\n'
         f'<text x="{x + 8 + tw / 2}" y="{y + 15}" fill="{tcolor}" font-size="7" font-family="{MONO}" '
         f'text-anchor="middle" letter-spacing="0.08em">{tag}</text>\n'
         f'<text x="{cx}" y="{cy + 6}" fill="{INK}" font-size="12" font-weight="600" font-family="{SANS}" '
         f'text-anchor="middle">{name}</text>\n')
    for i, line in enumerate(sub if isinstance(sub, list) else [sub]):
      s += (f'<text x="{cx}" y="{cy + 21 + i * 12}" fill="{MUTED}" font-size="9" font-family="{MONO}" '
            f'text-anchor="middle">{line}</text>\n')
    if badge:
      bw = text_w(badge) - 2
      s += (f'<rect x="{x + w - bw - 8}" y="{y + 6}" width="{bw}" height="12" rx="2" fill="{PAPER}" '
            f'stroke="rgba(45,49,66,0.22)" stroke-width="0.8"/>\n'
            f'<text x="{x + w - 8 - bw / 2}" y="{y + 15}" fill="{MUTED}" font-size="8" font-family="{MONO}" '
            f'text-anchor="middle">{badge}</text>\n')
    self.nodes.append(s)

  def legend_items(self, y, items, x0=40, width=984):
    out = [f'<line x1="{x0}" y1="{y - 8}" x2="{x0 + width}" y2="{y - 8}" stroke="rgba(45,49,66,0.10)" stroke-width="0.8"/>',
           f'<text x="{x0}" y="{y + 8}" fill="{MUTED}" font-size="8" font-family="{MONO}" letter-spacing="0.18em">LEGEND</text>']
    x = x0
    for kind, text in items:
      if kind in KIND:
        fill, stroke, dash, *_ = KIND[kind]
        dash = f' stroke-dasharray="{dash}"' if dash else ""
        out.append(f'<rect x="{x}" y="{y + 20}" width="14" height="10" rx="2" fill="{fill}" stroke="{stroke}" stroke-width="1"{dash}/>')
        tx = x + 20
      elif kind == "boundary":
        out.append(f'<rect x="{x}" y="{y + 20}" width="14" height="10" rx="2" fill="rgba(235,108,54,0.05)" '
                   f'stroke="rgba(235,108,54,0.50)" stroke-width="0.8" stroke-dasharray="3,2"/>')
        tx = x + 20
      else:
        c, w, dash, m = STROKE[kind]
        dash = f' stroke-dasharray="{dash}"' if dash else ""
        out.append(f'<line x1="{x}" y1="{y + 26}" x2="{x + 28}" y2="{y + 26}" stroke="{c}" stroke-width="{w}"{dash} marker-end="url(#{m})"/>')
        tx = x + 36
      out.append(f'<text x="{tx}" y="{y + 28}" fill="{MUTED}" font-size="8.5" font-family="{SANS}">{text}</text>')
      x = tx + len(text) * 5 + 28
    self.legend = out

  def svg(self, slug, w, h, title, desc):
    defs = "\n".join(
      f'<marker id="{i}" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">'
      f'<polygon points="0 0, 8 3, 0 6" fill="{c}"/></marker>'
      for i, c in (("arrow", MUTED), ("arrow-accent", ACCENT), ("arrow-link", LINK)))
    body = "\n".join(["<!-- zones -->", *self.zones, "<!-- arrows -->", *self.arrows,
                      "<!-- labels -->", *self.labels, "<!-- nodes -->", *self.nodes,
                      "<!-- legend -->", *self.legend])
    return (f'<svg viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg" role="img" '
            f'aria-labelledby="{slug}-title {slug}-desc">\n'
            f'<title id="{slug}-title">{title}</title>\n<desc id="{slug}-desc">{desc}</desc>\n'
            f'<defs>\n{defs}\n</defs>\n<rect width="100%" height="100%" fill="{PAPER}"/>\n{body}\n</svg>')


PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title}</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<style>
*, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
:root {{ --paper: #f5f5f5; --ink: #2d3142; --muted: #4f5d75; --rule: rgba(45,49,66,0.12); }}
body {{ font-family: 'Geist', system-ui, sans-serif; background: var(--paper); color: var(--ink); padding: 3rem 2rem; }}
.frame {{ max-width: 1120px; margin: 0 auto; }}
.eyebrow {{ font-family: 'Geist Mono', monospace; font-size: 0.66rem; font-weight: 500; letter-spacing: 0.18em;
  text-transform: uppercase; color: var(--muted); margin-bottom: 0.5rem; }}
h1 {{ font-family: 'Instrument Serif', serif; font-size: 2rem; font-weight: 400; letter-spacing: -0.02em; margin-bottom: 0.5rem; }}
.sub {{ color: var(--muted); font-size: 0.9rem; margin-bottom: 1.5rem; max-width: 70ch; }}
.scroll {{ overflow-x: auto; }}
svg {{ width: 100%; min-width: 900px; display: block; }}
.notes {{ margin-top: 1.5rem; display: grid; grid-template-columns: 1.2fr 1fr; gap: 1rem; }}
.card {{ background: #fff; border: 1px solid var(--rule); border-radius: 6px; padding: 1.25rem; font-size: 0.85rem; line-height: 1.5; }}
.card h3 {{ font-size: 0.9rem; margin-bottom: 0.5rem; }}
.card ul {{ padding-left: 1.1rem; }}
code {{ font-family: 'Geist Mono', monospace; font-size: 0.78rem; }}
footer {{ margin-top: 2rem; padding-top: 0.75rem; border-top: 1px solid var(--rule); font-family: 'Geist Mono', monospace;
  font-size: 0.66rem; color: var(--muted); }}
@media (max-width: 720px) {{ .notes {{ grid-template-columns: 1fr; }} body {{ padding: 2rem 1rem; }} }}
</style>
</head>
<body>
<div class="frame">
<p class="eyebrow">{eyebrow}</p>
<h1>{title}</h1>
<p class="sub">{sub}</p>
<div class="scroll">
{svg}
</div>
<div class="notes">
{cards}
</div>
<footer>SPEC-002 · SATAN system · generated by diagrams.py · host facts: ~/flakes/SATAN.md</footer>
</div>
</body>
</html>
"""


def card(title, items):
  lis = "".join(f"<li>{i}</li>" for i in items)
  return f'<div class="card"><h3>{title}</h3><ul>{lis}</ul></div>'


def page(path, slug, eyebrow, title, sub, d, w, h, desc, cards):
  with open(path, "w") as f:
    f.write(PAGE.format(eyebrow=eyebrow, title=title, sub=sub,
                        svg=d.svg(slug, w, h, title, desc), cards="\n".join(cards)))


# ---------------------------------------------------------------- context (current state)
def context(out):
  d = D()
  d.zone(240, 32, 480, 116, "BWRAP JAILS · UNTRUSTED", boundary=True)
  d.zone(792, 32, 208, 456, "POSTGRES-COUPLED")
  d.zone(216, 368, 528, 120, "FILE-COUPLED")

  # stub: systemd timers -> broker
  d.path("M 40,264 H 240", "default", "EMACSCLIENT", (140, 244))
  d.labels.append(f'<text x="40" y="288" fill="{SOFT}" font-size="9" font-family="{MONO}">systemd --user timers</text>')
  # broker -> harness (spawn, JSONL stdio)
  d.path("M 344,224 V 128", "default", "JSONL · STDIO", (352 + text_w("JSONL · STDIO") / 2, 170))
  # pi -> broker (MCP over UDS)
  d.path("M 616,128 V 224", "link", "MCP · UDS", (624 + text_w("MCP · UDS") / 2, 170))
  # broker -> postgres
  d.path("M 720,264 H 816", "default", "PSQL", (768, 244))
  # attrd <-> postgres (inbox tables + NOTIFY)
  d.path("M 896,128 V 224", "default", "INBOX · NOTIFY", (904 + text_w("INBOX · NOTIFY") / 2, 170))
  # patcher claims patch_jobs
  d.path("M 896,400 V 304", "dashed", "PATCH_JOBS", (904 + text_w("PATCH_JOBS") / 2, 346))
  # file-coupled peers
  d.path("M 312,400 V 304", "default", "FILES · RO", (320 + text_w("FILES · RO") / 2, 346))
  d.path("M 480,304 V 400", "default", "R/W", (488 + text_w("R/W") / 2, 346))
  d.path("M 648,304 V 400", "default", "QUEUE · EMIT", (656 + text_w("QUEUE · EMIT") / 2, 346))

  d.node(264, 64, 160, 64, "backend", "JAIL", "Run harness", "python → deepseek")
  d.node(536, 64, 160, 64, "backend", "JAIL", "Interactive pi", "jailed-pi · satan.ts")
  d.node(240, 224, 480, 80, "focal", "EMACS", "satan broker (Emacs daemon)",
         "~/dev/satan · policy · tools · audit · MCP server")
  d.node(816, 224, 160, 80, "store", "DB", "Postgres", "satan_memory")
  d.node(816, 64, 160, 64, "backend", "RUST", "satan-attrd", "attributes · decay")
  d.node(816, 400, 160, 64, "optional", "GO", "satan-patcher", "patch_jobs · dormant")
  d.node(240, 400, 144, 64, "backend", "PY", "panopticon", "~/.local/state/behaviour")
  d.node(408, 400, 144, 64, "store", "FS", "Text roots", "notes · ~/satan · state")
  d.node(576, 400, 144, 64, "backend", "RUST", "goad", "ask shell · goad.sock")
  d.legend_items(528, [("focal", "Focal: current authority"), ("backend", "Process"), ("store", "Store"),
                       ("optional", "Dormant"), ("boundary", "Trust boundary"),
                       ("default", "Spawn / read / write"), ("link", "RPC"), ("dashed", "Queue claim")])
  page(out, "satan-context", "SATAN · system context · current state (2026-09)",
       "SATAN as it runs today",
       "One Emacs daemon hosts the broker and every authority item. Peers couple to it through two "
       "buses: Postgres tables with NOTIFY, and plain files.",
       d, 1024, 580,
       "System context showing the Emacs-hosted satan broker spawning a jailed harness, serving MCP to "
       "interactive pi, and coupling to satan-attrd and satan-patcher through Postgres and to panopticon, "
       "goad and the text roots through files.",
       [card("Reading it", [
          "The <b>broker</b> is the only component that enacts actions; jailed agents propose over JSONL or MCP.",
          "<b>Postgres</b> doubles as an RPC bus: <code>satan_outcome_inbox</code>, <code>satan_audit_inbox</code>, "
          "<code>patch_jobs</code> + <code>pg_notify</code>. The broker LISTENs via <code>satan-attrd notify-stream</code>.",
          "Files: panopticon writes <code>behaviour/</code>; goad reads <code>state/goad/queue.json</code> and "
          "writes <code>~/satan/goad/data/</code>; the model-facing corpus is <code>~/satan</code>."]),
        card("Known gaps (SPEC-002 NF-003, NF-004)", [
          "Jails that serve MCP also bind the Emacs server socket: arbitrary elisp, bypassing the protocol.",
          "The harness inherits the Emacs cwd (<code>~</code>), and the jail binds <code>$PWD</code> read-write (probable; verify).",
          "The tick timer fires once per boot; the patcher has never completed a job."])])


# ---------------------------------------------------------------- composition (flake graph)
def composition(out):
  d = D()
  # flakes bar -> rank 1 (straight drops)
  d.path("M 312,120 V 184", "default")
  d.path("M 512,120 V 184", "default")
  d.path("M 696,120 V 184", "default")
  d.path("M 880,120 V 184", "default")
  # flakes -> ~/dev/satan working tree (timer ExecStart)
  d.path("M 264,120 V 152 Q 264,160 256,160 H 200 Q 192,160 192,168 V 184", "default",
         "EXECSTART", (228, 140))
  # emacs.d -> ~/dev/satan (load-path)
  d.path("M 128,120 V 184", "default", "LOAD-PATH", (88, 146))
  # cycle: satan pin -> nix-config (the repo ~/flakes lives in)
  d.path("M 376,184 V 120", "accent-dashed")
  d.label(384 + text_w("CYCLE") / 2, 146, "CYCLE", ACCENT)
  # rank 1 -> jail library
  d.path("M 512,240 V 304", "default")
  d.path("M 328,240 V 264 Q 328,272 336,272 H 464 Q 472,272 472,280 V 304", "default")
  d.path("M 696,240 V 264 Q 696,272 688,272 H 560 Q 552,272 552,280 V 304", "dashed", "OWN PIN",
         (624, 248))
  d.path("M 960,92 H 976 Q 984,92 984,100 V 324 Q 984,332 976,332 H 592", "default", "PATH:",
         (788, 312))
  # working tree vs pinned harness drift
  d.path("M 144,240 V 272 Q 144,280 152,280 H 280 Q 288,280 288,272 V 244", "dashed")
  d.label(216, 288, "DRIFT", MUTED)

  d.node(64, 64, 160, 56, "external", "CONFIG", "~/.emacs.d", "require dl-satan", badge="0 in")
  d.node(248, 64, 712, 56, "backend", "HOST", "host flake  (~/flakes = the nix-config repo)",
         "NixOS + home-manager: systemd units, packages, postgres, jail library", badge="1 in")
  d.node(64, 184, 160, 56, "backend", "TREE", "~/dev/satan", "elisp + bin/ (live)", badge="2 in")
  d.node(248, 184, 160, 56, "backend", "PIN", "satan @ github", "harness binary", badge="1 in")
  d.node(432, 184, 160, 56, "backend", "PATH", "3 path: inputs", "attrd · panopticon · patcher", badge="1 in")
  d.node(616, 184, 160, 56, "backend", "GIT", "goad", "git+file · no follows", badge="1 in")
  d.node(800, 184, 160, 56, "external", "PIN", "oubliette", "microvm host module", badge="1 in")
  d.node(432, 304, 160, 56, "store", "LIB", "jail library", "~/flakes/agents · bwrap", badge="4 in")
  d.legend_items(400, [("backend", "Flake / tree"), ("external", "Config or external pin"),
                       ("store", "Shared library"), ("default", "Input / loads"),
                       ("dashed", "Separate copy · drift"), ("accent-dashed", "Cycle")])
  page(out, "satan-composition", "SATAN · composition · how the repos are wired",
       "Who composes whom",
       "~/flakes is the de facto composition root. It pins the harness from GitHub while systemd "
       "runs scripts and Emacs loads elisp from the live working tree.",
       d, 1024, 452,
       "Dependency graph showing ~/flakes consuming satan, attrd, panopticon, satan-patcher, goad and "
       "oubliette as flake inputs, all converging on the shared jail library, with a cycle from satan back "
       "to the nix-config repo.",
       [card("Reading it", [
          "<b>CYCLE</b>: satan's <code>agents</code> input is <code>github:davidlee/nix-config?dir=flakes/agents</code>, "
          "the repo ~/flakes lives in, while ~/flakes takes satan as an input. ~/flakes breaks the loop at eval "
          "time with <code>follows</code>; standalone builds of satan take a different library rev.",
          "<b>DRIFT</b>: one running system mixes two revisions of satan: the pinned harness and the live elisp and bin scripts.",
          "<b>OWN PIN</b>: goad has no <code>follows</code>, so it builds against its own copy of the jail library "
          "(the deprecated <code>flakes/pub</code> alias)."]),
        card("Not shown", [
          "Every repo's own dev jails (<code>jailed-pi</code> etc.) and their divergent mounts: see ~/flakes/SATAN.md.",
          "~/satan (corpus) and ~/notes flakes: they define interactive jails only.",
          "Postgres is configured by ~/flakes, but <code>satan_memory</code> is created and migrated by hand."])])


# ---------------------------------------------------------------- end state (ADR-017/018)
def end_state(out):
  d = D()
  d.zone(240, 32, 480, 116, "BWRAP JAILS · UNTRUSTED", boundary=True)
  d.zone(216, 368, 528, 120, "DATA PLANE · DURABLE LOGS + FILES")

  d.path("M 344,224 V 128", "default", "JSONL · STDIO", (352 + text_w("JSONL · STDIO") / 2, 170))
  d.path("M 616,128 V 224", "link", "MCP", (624 + text_w("MCP") / 2, 170))
  d.path("M 184,264 H 240", "link", "RPC", (212, 244))
  d.path("M 816,256 H 720", "link", "RPC · UDS", (768, 236))
  d.path("M 720,288 H 776 Q 784,288 784,296 V 424 Q 784,432 792,432 H 816", "default", "SQL · STATE",
         (792 + text_w("SQL · STATE") / 2, 346))
  d.path("M 312,400 V 304", "default", "READ LOGS", (320 + text_w("READ LOGS") / 2, 346))
  d.path("M 480,304 V 400", "default", "R/W", (488 + text_w("R/W") / 2, 346))
  d.path("M 648,304 V 400", "default", "QUEUE · EMIT", (656 + text_w("QUEUE · EMIT") / 2, 346))

  d.node(264, 64, 160, 64, "backend", "JAIL", "Run harness", "python → provider")
  d.node(536, 64, 160, 64, "backend", "JAIL", "Interactive pi", "jailed-pi")
  d.node(240, 224, 480, 80, "focal", "CORE", "satan core daemon",
         ["policy + registry (read-only artifact) · runs · attributes", "one repo · Cargo workspace · owns migrations"])
  d.node(40, 224, 144, 80, "input", "CLIENT", "Emacs", ["approval surfaces", "org / denote handlers"])
  d.node(816, 400, 160, 64, "store", "DB", "Postgres", "state store, not a bus")
  d.node(816, 224, 160, 80, "optional", "PROPOSED", "patch runner", "→ oubliette capsule")
  d.node(240, 400, 144, 64, "backend", "PY", "panopticon", "append-only logs")
  d.node(408, 400, 144, 64, "store", "FS", "Text roots", "notes · ~/satan · state")
  d.node(576, 400, 144, 64, "backend", "RUST", "goad", "ask shell")
  d.legend_items(528, [("focal", "Owner of policy + registry"), ("backend", "Process"), ("input", "Client"),
                       ("store", "Store"), ("optional", "Proposed, undecided"), ("boundary", "Trust boundary"),
                       ("link", "Control plane (RPC)"), ("default", "Data plane")])
  page(out, "satan-end-state", "SATAN · target end-state · ADR-017 / ADR-018",
       "Emacs as a client",
       "The destination the accepted ADRs describe: a headless core owns policy, the tool registry and "
       "run lifecycle; Emacs keeps the human approval surfaces; Postgres stops being an RPC bus.",
       d, 1024, 580,
       "Target architecture in which a satan core daemon owns policy, registry, runs and attributes, "
       "serves Emacs and the patch runner over Unix-socket RPC, spawns the jailed harness, and reads "
       "panopticon logs and text roots as a data plane.",
       [card("What moves", [
          "ADR-018 D1: satan-attrd is absorbed into the core repo; one migration owner for <code>satan_memory</code>.",
          "ADR-018 D2: the mode/tool/capability/budget table leaves <code>satan-mode.el</code> and becomes a "
          "read-only artifact every surface reads.",
          "ADR-018 D3: inbox tables + <code>pg_notify</code> + <code>notify-stream</code> retire in favour of UDS RPC.",
          "ADR-018 D4 order: rehearse in elisp → policy + registry → handlers by substrate → run execution last."]),
        card("Not decided here", [
          "Process count and binary split of the core (ADR-018 OQ-1).",
          "The patch runner's home: satan-patcher is Go and outside the core repo; oubliette is its proposed jail.",
          "Where MCP is served once Emacs no longer holds the registry."])])


if __name__ == "__main__":
  outdir = sys.argv[1]
  context(f"{outdir}/context.html")
  composition(f"{outdir}/composition.html")
  end_state(f"{outdir}/end-state.html")
