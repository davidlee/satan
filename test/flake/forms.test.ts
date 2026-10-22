// Static assertions over the flake's per-call launch forms (design sec-3,
// "Per-call mode"; SL-029 PHASE-09; quotient SL-031 PHASE-10).
//
// This is the nix-free half: it reads flake.nix as text, so it runs on a host
// with no `nix` binary. It pins the intent — one form per capability, the root
// flag each one carries, the run-time session bind, the one-positional
// contract — and nothing more.
//
// It is NOT the bind-set proof. That is the `quotient-forms` flake check, which
// reads the BUILT launchers and fails on a bind that was added or dropped; a
// textual assertion cannot see what the shared generator renders. The two are
// not interchangeable and neither substitutes for the other.
//
// One generator (`quotientFormFamily`) renders both forms, so the assertions
// run over its text.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const flake = readFileSync(new URL('../../flake.nix', import.meta.url), 'utf8');

/** The text between two anchors, both required and both kept. */
function region(text: string, start: string, end: string): string {
  const from = text.indexOf(start);
  assert.notEqual(from, -1, `flake.nix must contain ${JSON.stringify(start)}`);
  const to = text.indexOf(end, from + start.length);
  assert.notEqual(to, -1, `flake.nix must contain ${JSON.stringify(end)} after ${start}`);
  return text.slice(from, to);
}

const generator = region(flake, 'quotientFormFamily = let', 'quotientForms =');

test('one form per capability, built on the shared jail generator without its launch-dir mount', () => {
  assert.match(generator, /"\$\{prefix\}-read" = mkForm "read";/);
  assert.match(generator, /"\$\{prefix\}-write" = mkForm "write";/);
  assert.match(generator, /jailLib\.makeJailedPi \{/);
  // The generator's own launch dir is a rw `--bind` at /workspace/<basename>:
  // the wrong strength for read and the wrong path for both.
  assert.match(generator, /mountLaunchDir = false;/);
  // One generator call, shared by every form and the check's baseline.
  assert.equal(generator.match(/jailLib\.makeJailedPi \{/g)?.length, 1);
  assert.match(generator, /formJail = jail name \[/);
  assert.match(generator, /baseline = jail "\$\{prefix\}-baseline" \[\];/);
});

test('the family carries its own name and session variable', () => {
  assert.match(generator, /prefix = "quotient";/);
  assert.match(generator, /sessionVar = "QUOTIENT_ACTIVE_SESSION_DIR";/);
});

test('the forms are checked by quotient-forms', () => {
  assert.match(flake, /quotient-forms = quotientFormsCheck;/);
  assert.doesNotMatch(flake, /pi-mcp/);
});

test('the root bind is read-only for read and writable for write, at its own absolute path', () => {
  assert.match(
    generator,
    /if capability == "read"\s*\n\s*then ''--ro-bind "\$PWD" "\$PWD"''\s*\n\s*else ''--bind "\$PWD" "\$PWD"''/,
  );
  assert.doesNotMatch(generator, /--ro-bind "\$PWD" "\/workspace\//);
});

test('the active session directory is bound from the run-time variable, not the home and not the run dir', () => {
  // The variable is the family's `sessionVar`, both bound and exported.
  assert.match(generator, /rawArg \("--bind \\"\$" \+ sessionVar \+ "\\" \\"\$" \+ sessionVar \+ "\\""\)/);
  assert.match(generator, /export \$\{sessionVar\}="\$session_dir"/);
  // A bind of the session home would reach every session, and a bind of the
  // run directory would reach the evidence (design sec-3, sec-6).
  assert.doesNotMatch(generator, /--(ro-)?bind[^\n]*(SESSION_HOME|RUN_DIR)/);
});

test('the jail gets a tmpfs /tmp and no workspace or home mount', () => {
  assert.match(generator, /--tmpfs \/tmp/);
  assert.doesNotMatch(generator, /--(ro-)?bind[^\n]*\/workspace\//);
});

test('each form consumes exactly one positional and forwards the rest with no executable word and no `--`', () => {
  assert.match(generator, /session_dir=\$1/);
  assert.match(generator, /^\s*shift\b/m);
  assert.match(generator, /exec \$\{formJail\}\/bin\/jailed-\$\{name\} "\$@"$/m);
  // No second positional, and nothing appended to the forwarded argv.
  assert.doesNotMatch(generator, /\$2\b/);
  assert.doesNotMatch(generator, /exec [^\n]*"\$@"[^\n]*--/);
});

test('the argument guards each exit 64 (usage)', () => {
  // Missing, relative and non-directory session paths: three guards, no more.
  assert.equal(generator.match(/exit 64/g)?.length, 3);
});

test('--die-with-parent is a raw launcher arg on every form', () => {
  assert.match(generator, /rawArg "--die-with-parent"/);
  assert.equal(generator.match(/--die-with-parent/g)?.length, 1);
});

test('the flake carries the bind-set probes and the checks that read the built launchers', () => {
  const probes = region(flake, 'formProbes = let', 'launcherCheck =');
  assert.match(probes, /read = \{/);
  assert.match(probes, /write = \{/);
  assert.match(probes, /envPrefix = "QUOTIENT";/);
  // The expected residue over the generator's own jail is root + session
  // directory; the generator's binds are derived from a baseline built by the
  // same call, never listed, so a generator change cannot fail or move it.
  assert.doesNotMatch(probes, /shared = \[/);
  assert.match(flake, /quotientFormsCheck = let/);
  assert.match(flake, /\(f\) G7/);
});
