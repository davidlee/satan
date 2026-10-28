From SL-034 (2026-10-28):

- The host's default quotient forms carry no project toolchain by rule. A root
  whose gate needs node (malebolge) gets its own forms: `just quotient-forms`
  then `quotient allow` per form (malebolge f611305, user-approved for
  `implement`/`write`). Until a form is approved its profile is refused
  `form-unapproved`; malebolge's read-side profiles (`read`, `research`,
  `judgement`, `review`) stay refused until the user approves the read form.
- Inside that sandbox `npx biome` fails without the nix glibc loader
  (`/lib64/ld-linux` absent), and `git-guarded` refuses `reset --hard` /
  `clean -ffd`, so 4 `test/runner/{collect,recovery}` tests fail in-sandbox
  (green on host). Run the final gate on the host.
- malebolge's structure test fails on the word "capsule" anywhere in `src/`
  (door-knowledge rule), comments included.
- pi workers spending their 30-request ceiling
  on reading dist or `.doctrine/` never answer; point them at exact files.
