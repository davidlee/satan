# Notes SL-024: malebolge: advertise Agent Skills in the system prompt

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Review continuation

Critical reading recorded on RV-028. The design document was left unchanged.
An additional pass would be useful after responses are integrated: check that
the compatibility claims match the resulting parsing/loading contract and that
the deployment assertion can reject an incorrect skill suffix. A broader
architectural pass is not warranted by the current scope.

Review artifacts are uncommitted; this session did not land a commit. No code
changed, and no implementation gate or live deployment verification was run.

### After integration (design-run rev 26)

F-1..F-3 integrated into sec-4/6/7 and disposed `fix-now` on RV-028
(F-3 partial: `SKILL.md` asserted, bundled reference files not). A further
pass would probe exactly the continuation above: parsing predicates and
duplicate rules against pi `skills.ts:120,320,420-455`, and the
`malebolge-jail-profile` negative control. The user waived that pass on
2026-10-19 ("reviewed, let's lock and plan"); the raiser's verification of
the three answers stays open on RV-028 and is not a lock blocker (all minor).
Both probes are VT rows in sec-6, so implementation exercises them.

## Plan approval

2026-10-19: the user approved plan.toml (reply "yes" to "Approve plan.toml?"). Execution chartered to a capsule orchestrator, PHASE-01..03.

### PHASE-02 smoke (EX-5)

2026-10-19, M working tree on top of 9eb1123 (PHASE-02 delta uncommitted at the time). Scratch `XDG_STATE_HOME` and `MALEBOLGE_SOCKET` (short `/tmp/ms-*` path: the session-scratchpad socket path exceeded the unix socket limit, `listen EINVAL`), `timeout -s TERM 15 node src/daemon-main.ts`, both runs exit 124 (expected). Scratch state removed afterwards.

Run 1, `MALEBOLGE_SKILLS=~/dev/goad/kit/skills/goad-backend`:

    malebolge: gateway/deepseek-flash · 37 SATAN tools · 1 skills
    malebolge: session <scratch>/state/satan/durable/session.sqlite
    malebolge: attach  /tmp/ms-XXXX/d.sock

Run 2, same plus `:/nonexistent/skill`:

    malebolge: skill /nonexistent/skill: ENOENT: no such file or directory, open '/nonexistent/skill/SKILL.md'
    malebolge: gateway/deepseek-flash · 37 SATAN tools · 1 skills
    malebolge: attach  /tmp/ms-XXXX/d.sock

The bad entry is skipped and logged; the daemon still starts. `session.sqlite` appeared under the scratch state dir only.

### PHASE-03 flake check (EX-2, EX-3, VA-1)

2026-10-19, satan working tree (flake.nix uncommitted). goad-kit: `/nix/store/vx4wawpgk49phj98rlzcpwqqx48xkbrm-goad-kit`. Baseline before edit: `nix build --no-link .#checks.x86_64-linux.malebolge-jail-profile` green; `flake.nix`/`flake.lock` clean. Edit: `goadSkill` binding, `(set-env "MALEBOLGE_SKILLS" goadSkill)`, probe `--setenv MALEBOLGE_SKILLS ${goadSkill}`, `test -r ${goadSkill}/SKILL.md || fail ...`. Rebuilt launcher renders `--setenv MALEBOLGE_SKILLS /nix/store/vx4wawpgk49phj98rlzcpwqqx48xkbrm-goad-kit/kit/skills/goad-backend` (unquoted, as designed). `alejandra -c flake.nix` clean.

C1, suffix changed to `goad-backend-WRONG` (the setenv probe still passes; the SKILL.md test catches it):

    malebolge-jail-profile: no goad-backend skill at /nix/store/vx4wawpgk49phj98rlzcpwqqx48xkbrm-goad-kit/kit/skills/goad-backend-WRONG
    error: builder for '…-malebolge-jail-profile.drv' failed with exit code 1

C2, `(set-env "MALEBOLGE_SKILLS" goadSkill)` removed:

    malebolge-jail-profile: launcher must contain '--setenv MALEBOLGE_SKILLS /nix/store/vx4wawpgk49phj98rlzcpwqqx48xkbrm-goad-kit/kit/skills/goad-backend'
    error: builder for '…-malebolge-jail-profile.drv' failed with exit code 1

Both reverted by editing the file back (byte-compared against a pre-control copy); `git diff flake.nix` shows only the four intended hunks (+11 lines). Final: the profile check green; `nix flake check` green ("running 3 flake checks", only the aarch64-darwin omission warning).

Pending human acts: EX-4 (delete the malebolge handover doc), VH-1 (live run).

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · ready · b616a58

### Produced

- Scope, research, locked design (run dr-01a151c7), plan + 3 phase sheets (commit b616a58). No code yet.
- RV-028 — GPT design review; F-1..F-3 integrated into design §4/6/7.

### Learned

- Nothing new for memory; handover-era nix facts superseded by CHR-018 (recorded in slice-024.md Context).

### Open

- RV-028 — raiser verification of F-1..F-3 answers outstanding (minor; not a lock blocker).
- DEC-066 — yaml parser; DEC-067 — read once at startup (both shape PHASE-01/02).
