// Static assertions over the flake's per-call launch forms (design sec-3,
// "Per-call mode"; SL-029 PHASE-09; quotient SL-031 PHASE-10).
//
// This is the nix-free half: it reads flake.nix as text, so it runs on a host
// with no `nix` binary. It pins the intent — one form per capability, the root
// flag each one carries, the run-time session bind, the one-positional
// contract — and nothing more.
//
// It is NOT the bind-set proof. That is the `<prefix>-forms` flake check, which
// reads the BUILT launchers and fails on a bind that was added or dropped; a
// textual assertion cannot see what the shared generator renders. The two are
// not interchangeable and neither substitutes for the other.
//
// One generator (`mkFormFamily`) renders every family, so the shared
// assertions run once over its text and the per-family ones run over a table.
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

const generator = region(flake, 'mkFormFamily = {', 'formFamilies = {');
const families = region(flake, 'formFamilies = {', 'piMcpForms =');

const FAMILIES = [
  { prefix: 'pi-mcp', sessionVar: 'PI_MCP_ACTIVE_SESSION_DIR', dieWithParent: false },
  { prefix: 'quotient', sessionVar: 'QUOTIENT_ACTIVE_SESSION_DIR', dieWithParent: true },
];

test('one form per capability, built on the shared jail generator without its launch-dir mount', () => {
  assert.match(generator, /"\$\{prefix\}-read" = mkForm "read";/);
  assert.match(generator, /"\$\{prefix\}-write" = mkForm "write";/);
  assert.match(generator, /jailLib\.makeJailedPi \{/);
  // The generator's own launch dir is a rw `--bind` at /workspace/<basename>:
  // the wrong strength for read and the wrong path for both.
  assert.match(generator, /mountLaunchDir = false;/);
  // One generator call, shared by every form and the check's baseline.
  assert.equal(generator.match(/jailLib\.makeJailedPi \{/g)?.length, 1);
  assert.match(generator, /formJail = jail name \(/);
  assert.match(generator, /baseline = jail "\$\{prefix\}-baseline" \[\];/);
});

for (const { prefix, sessionVar, dieWithParent } of FAMILIES) {
  test(`${prefix}: the family is instantiated with its own name, session variable and parent policy`, () => {
    const instance = region(families, `${prefix} = mkFormFamily {`, '};');
    assert.match(instance, new RegExp(`prefix = "${prefix}";`));
    assert.match(instance, new RegExp(`sessionVar = "${sessionVar}";`));
    assert.match(instance, new RegExp(`dieWithParent = ${dieWithParent};`));
  });
}

test('the forms name quotient-read and quotient-write', () => {
  assert.match(families, /prefix = "quotient";/);
  // The names are `${prefix}-<capability>`, so the literal pair is pinned by
  // the check probes and the built-package names the justfile and policy use.
  assert.match(flake, /quotient-forms = mkFormCheck "quotient";/);
  assert.match(flake, /pi-mcp-forms = mkFormCheck "pi-mcp";/);
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

test('--die-with-parent is added by the family flag alone, as a raw launcher arg', () => {
  assert.match(generator, /lib\.optional dieWithParent \(rawArg "--die-with-parent"\)/);
  // No other spelling slips it into the shared options.
  assert.equal(generator.match(/--die-with-parent/g)?.length, 1);
});

test('the flake carries the bind-set probes and the checks that read the built launchers', () => {
  const probes = region(flake, 'formProbes = {', 'launcherCheck =');
  assert.match(probes, /read = \{/);
  assert.match(probes, /write = \{/);
  assert.match(probes, /envPrefix = "PI_MCP";/);
  assert.match(probes, /envPrefix = "QUOTIENT";/);
  assert.match(probes, /dieWithParent = true;/);
  // The expected residue over the generator's own jail is root + session
  // directory; the generator's binds are derived from a baseline built by the
  // same call, never listed, so a generator change cannot fail or move it.
  assert.doesNotMatch(probes, /shared = \[/);
  assert.match(flake, /mkFormCheck = prefix: let/);
  assert.match(flake, /\(f\) G7/);
});
