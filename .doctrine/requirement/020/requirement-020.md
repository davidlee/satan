# REQ-020: The child environment has one base: the editor's global environment

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

ISS-037: the child env used to follow the calling buffer's direnv merge. One base, the editor's global env, makes the spawn contract independent of who starts the run. Since SL-022 the broker resolves no credential, so the SL-018 RV-013 N5 coupling (lookup env = child env) is gone, and excluding unresolved refs is the jail's job: it starts from `env -i` (REQ-025). The launcher process outside the jail still inherits the editor env until emacs:SL-015.
