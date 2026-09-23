Observed by the keeper, 2026-09-23 (op 2.x, desktop-app integration):

- **The prompt belongs to the session, not the read.** `op signin` raises the
  1Password authorization dialog; `op read op://…` inside a live session does
  not. A cold `op read` with no session prompts because it has to *establish*
  one — that is the prompt behind [[mem.fact.satan.op-read-blocks-emacs-server]].
- **`op whoami` is a non-prompting probe.** Signed out, it fails fast and quietly:

      $ time op whoami
      [ERROR] … account is not signed in      # exit 1, ~0.00s, no dialog

  So "is there a live session?" is answerable without risking a prompt.
- **Killing a pending `op` does NOT dismiss its dialog.** A timeout-and-kill
  read (`timeout 5 op read …`) leaves the popup on screen; accepting it then
  authorizes nothing the caller is waiting for. A bounded read therefore
  *orphans* prompts — worse than letting the read block on a visible dialog.

Design consequences (SATAN unattended runs, ISS-012 / the AUTH slice):

- Gate unattended resolution on `op whoami`: live session → read (silent);
  no session → defer or deliberately prompt, per mode policy.
- Residual race (session expires between probe and read) costs one visible
  prompt, not a hidden hang — acceptable.
- Do not "fix" blocking with a timeout; see the third bullet.

Reproduced twice on 2026-09-23 (EVD-003). What remains unproven is the
*failure* case, not the success case: whether a session can stay live (`op
whoami` exits 0) yet make a later read re-authenticate, after some interval or
condition. Positive reads are no evidence that this never happens, so ASM-002
is held and watched, not "validated by one clean test". Its cost is bounded:
one visible, labelled prompt.

- **The dialog expires on its own after ~1–2 min**, and `op` reports that as
  `authorization prompt dismissed`, the same as a keeper dismissal (observed
  2026-09-23, SL-018 PHASE-08, run `20260923T221713-motd`). A blocking read
  therefore waits for the keeper for about a minute or two, not indefinitely.
  An unattended prompting run with nobody at the desk fails
  (`credential_unavailable`), and no late acceptance is possible. See ISS-023
  and DEC-020's RV-014 note.
