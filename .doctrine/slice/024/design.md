<!-- doctrine:section sec-1 -->
# 1. Design Problem

Interactive SATAN has two hosts. Under `jpi` (pi-coding-agent) it sees
**Agent Skills**: directories holding a `SKILL.md` whose YAML frontmatter
gives a `name` and a `description`. Pi lists each skill in the system prompt
and the model `read`s the full file only when a task matches (progressive
disclosure). malebolge, SATAN's durable session daemon on pi-durable, has no
skill loading, so SATAN under malebolge cannot find `goad-backend`, the kit
it uses to write goad backends.

This design adds the listing to malebolge, in pi's own wording, fed by an
env var that the jail sets to the pinned `goad-backend` store path.

<!-- doctrine:section sec-2 -->
# 2. Current State

```
satan flake.nix                     malebolge daemon-main.ts
───────────────                     ────────────────────────
malebolgeJailOptions                resolveConfig(env)
  set-env GATEWAY_KEY_FILE   ──env──▶   Config { corpusRoot, … }
  set-env GATEWAY_CATALOG              │
goadPkgs (goad-kit) in closure         ▼
                                    extensions: [persona, CodingTools, satan]
                                       │  persona: section("persona", re-read files)
                                       ▼
                                    system prompt  ── no skills listed
```

- `src/persona.ts:20-24` is the precedent: one `defineExtension`, one
  `section(key, render, { tag: false })`.
- pi-durable omits a section whose `render` returns `undefined`
  (`dist/harness/prompt.js:38`).
- `goad.goad-kit` is already in `jailed-malebolge`'s closure
  (`flake.nix:243,319`); nothing points the daemon at it.

<!-- doctrine:section sec-3 -->
# 3. Forces & Constraints

**Binding governance** (confirmed for this run):

- SPEC-002 NF-006 (REQ-018): no host literals. The skill path enters only
  through `MALEBOLGE_SKILLS`.
- SPEC-002 NF-004 (REQ-016): the jail profile is test-asserted. The
  `malebolge` jail-profile probe asserts the new setenv.
- SPEC-002 NF-003 (REQ-015): one revision per repo. The skill comes from
  satan's pinned `goad` input.

**Decisions:**

- DEC-066: parse frontmatter with the `yaml` package, as pi does.
- DEC-067: read skills once at startup.

**Forces:** both hosts must prompt the same way (copy pi's wording and rules
from pi 1.3.0, the version malebolge pins); a bad skill must never stop the
daemon.

<!-- doctrine:section sec-4 -->
# 4. Design

## Module: `src/skills.ts`

```ts
export interface Skill { name: string; description: string; file: string; hidden: boolean }

/** A skill from its directory and SKILL.md text, or why it is skipped. */
export const parseSkill = (dir: string, text: string): Skill | string

/** Read each directory's SKILL.md; log and drop the ones that fail. */
export const loadSkills = (dirs: readonly string[], log: (line: string) => void): Skill[]

/** Pi's listing for the visible skills, or undefined when there are none. */
export const renderSkills = (skills: readonly Skill[]): string | undefined

export const skillsExtension = (skills: readonly Skill[]): Extension
  // defineExtension({ name: "skills", sections: [section("skills", () => text, { tag: false })] })
```

`parseSkill` and `renderSkills` are pure. `loadSkills` is the only IO in
the module (`readFileSync`), and its only side effect is `log`. The
`Skill[]` value is computed once and closed over by the extension
(DEC-067).

## Parsing rules (from pi `skills.ts:285-345`, `frontmatter.ts`)

1. Strip a BOM and normalise newlines. If the text doesn't start with
   `---`, or there is no closing `\n---`, the frontmatter is empty.
2. Parse it with `yaml`'s `parse` (DEC-066). A parse error, or a result
   that isn't a mapping, skips the skill with the reason.
3. `description` must be a string with `description.trim() !== ""`, or
   the skill is skipped. A whitespace-only description is skipped. The
   advertised text is the description as written, untrimmed, as in pi.
4. `name` is `frontmatter.name` when it is a non-empty string (pi's
   `name || dirName`). A missing, non-string or empty `name` falls back to
   `basename(dir)`.
5. `hidden` is `disable-model-invocation === true`.
6. `file` is `join(dir, "SKILL.md")`.

A missing or unreadable `SKILL.md` is a skip, logged as
`skill <dir>: <reason>`.

## Duplicates (from pi `skills.ts:420-455`)

`loadSkills` works through `dirs` in order:

- If a `SKILL.md` resolves (via `realpathSync`) to a file already loaded,
  it is skipped silently, so a repeated or symlinked entry lists once.
- If a skill's `name` matches one already kept, the **first one wins**. The
  later one is dropped and logged as
  `skill <dir>: name "<name>" collides with <winner file>`.

## Rendering (from pi `formatSkillsForPrompt`, `skills.ts:358-397`)

Visible skills only. Pi's three instruction lines, using the `read`
variant because `CodingTools` provides `read`, then:

```
<available_skills>
  <skill>
    <name>…</name>
    <description>…</description>
    <location>…/SKILL.md</location>
  </skill>
</available_skills>
```

Name, description and location are XML-escaped (`& < > " '`). Pi's leading
`\n\n` is dropped: in pi it joins the listing onto the preceding prompt
text, while here it is a section of its own.

## Config

`Config.skillDirs: string[]` (directories, not parsed skills), from `MALEBOLGE_SKILLS` split on `:` with empty
segments dropped. Unset or empty gives `[]`.

## Wiring (`daemon-main.ts`)

```ts
const skills = loadSkills(config.skillDirs, log);
extensions: [personaExtension(…), skillsExtension(skills), CodingTools, satan.extension]
log(`… · ${String(skills.length)} skills`)   // in the existing startup line
```

The skills section comes straight after the persona section, matching
pi's order (system prompt, then skills).

## Deployment (`~/dev/satan/flake.nix`)

```nix
goadSkill = "${goad.goad-kit}/kit/skills/goad-backend";
malebolgeJailOptions = [ … (set-env "MALEBOLGE_SKILLS" goadSkill) ];
jailProbes.malebolge.present = [ … "--setenv MALEBOLGE_SKILLS ${goadSkill}" ];
```

`malebolgeJailProfile` also checks the package itself, not only the
launcher text: `test -r ${goadSkill}/SKILL.md || fail "no goad-backend skill
at …"`. A wrong suffix then fails `nix flake check` instead of being logged
and dropped at runtime. The check asserts only `SKILL.md`, not the skill's
`reference/` files; those belong to goad's layout, and the live check
exercises them.

<!-- doctrine:section sec-5 -->
# 5. Code Impact

malebolge (`~/dev/malebolge`, its own repo, so selectors cannot fence it):

| Path | Change |
|---|---|
| `src/skills.ts` | new: `parseSkill`, `loadSkills`, `renderSkills`, `skillsExtension` |
| `test/skills.test.ts` | new |
| `src/config.ts` | `skillDirs` field, `MALEBOLGE_SKILLS` |
| `test/config.test.ts` | env parsing cases |
| `src/daemon-main.ts` | load, wire, log count |
| `package.json`, `package-lock.json` | `yaml` runtime dependency |
| `README.md`, `docs/internals.md` | env var and extension list |
| `eslint.config.js` | ignore `.pi` (doctrine-vendored extensions sit outside tsconfig; type-aware lint baseline fix) |
| `test/harness-fixture.ts` | shared `systemPromptSections` helper |
| `test/persona.test.ts` | moved onto that helper |

satan (this repo): `flake.nix` (`malebolgeJailOptions`, `jailProbes.malebolge`).

<!-- doctrine:section sec-6 -->
# 6. Verification

| Criterion | Mode | How |
|---|---|---|
| `parseSkill` cases: plain, quoted, folded (`>`), block (`\|`), no frontmatter, unclosed, missing / non-string / empty / whitespace-only description, name missing / non-string / `""` (each falls back to dir name), hidden flag, YAML error, non-mapping | VT | `test/skills.test.ts` |
| `renderSkills`: pi's text byte for byte for a sample; escaping; hidden filtered; all hidden or none gives `undefined` | VT | `test/skills.test.ts` |
| `loadSkills`: a missing dir and a bad skill are logged and dropped; good ones kept in order; a repeated dir and a symlinked dir list once without a log line; a name collision keeps the first and logs the second | VT | temp dirs via `tempDir` |
| The section reaches a turn's system prompt; no skills means no `skills` key | VT | `openTestHarness`, as in `test/persona.test.ts:33-53` |
| `MALEBOLGE_SKILLS` parsing: unset, empty, `a::b:` | VT | `test/config.test.ts` |
| malebolge gate: tests, lint, typecheck, format | VT | `justfile` |
| Jail profile asserts the setenv, and `${goadSkill}/SKILL.md` is readable | VT | `nix flake check` in satan (`malebolge-jail-profile`); a deliberately wrong suffix makes it fail once (negative control, recorded in notes) |
| SATAN names `goad-backend`; reads its `SKILL.md` before writing a backend; the backend passes `goad-check` | VH | live session, run by the user |

<!-- doctrine:section sec-7 -->
# 7. Risks & Open Edges

- **Wording drift from pi.** Pi may change its wording; we accept that the
  hosts can then differ. The pi version the wording came from (1.3.0) is
  recorded in a code comment.
- **Store layout assumption.** `kit/skills/goad-backend` inside `goad-kit`
  is taken from `~/notes/flake.nix:56`. The flake check asserts that
  `SKILL.md` exists there (RV-028 F-3); the live check covers the rest.
- **Non-store skill dirs** need a daemon restart after an edit (DEC-067).

