// Static assertions over the flake's per-call launch forms (design sec-3,
// "Per-call mode"; SL-029 PHASE-09).
//
// This is the nix-free half: it reads flake.nix as text, so it runs on a host
// with no `nix` binary. It pins the intent — one form per capability, the root
// flag each one carries, the run-time session bind, the one-positional
// contract — and nothing more.
//
// It is NOT the bind-set proof. That is the `pi-mcp-forms` flake check, which
// reads the BUILT launchers and fails on a bind that was added or dropped; a
// textual assertion cannot see what the shared generator renders. The two are
// not interchangeable and neither substitutes for the other.
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

const forms = region(flake, 'piMcpJail = ', 'jailPkgs =');

test('one form per capability, built on the shared jail generator without its launch-dir mount', () => {
  assert.match(forms, /pi-mcp-read = mkForm "read";/);
  assert.match(forms, /pi-mcp-write = mkForm "write";/);
  assert.match(forms, /jailLib\.makeJailedPi \{/);
  // The generator's own launch dir is a rw `--bind` at /workspace/<basename>:
  // the wrong strength for read and the wrong path for both.
  assert.match(forms, /mountLaunchDir = false;/);
  // One generator call, shared by both forms and the check's baseline.
  assert.equal(forms.match(/jailLib\.makeJailedPi \{/g)?.length, 1);
  const mkForm = region(forms, 'mkForm = capability:', 'pi-mcp-read = mkForm "read";');
  assert.match(mkForm, /jail = piMcpJail name \[/);
});

test('the root bind is read-only for read and writable for write, at its own absolute path', () => {
  assert.match(
    forms,
    /if capability == "read"\s*\n\s*then ''--ro-bind "\$PWD" "\$PWD"''\s*\n\s*else ''--bind "\$PWD" "\$PWD"''/,
  );
  assert.doesNotMatch(forms, /--ro-bind "\$PWD" "\/workspace\//);
});

test('the active session directory is bound from the run-time variable, not the home and not the run dir', () => {
  assert.match(forms, /--bind "\$PI_MCP_ACTIVE_SESSION_DIR" "\$PI_MCP_ACTIVE_SESSION_DIR"/);
  assert.match(forms, /export PI_MCP_ACTIVE_SESSION_DIR="\$session_dir"/);
  // A bind of the session home would reach every session, and a bind of the
  // run directory would reach the evidence (design sec-3, sec-6).
  assert.doesNotMatch(forms, /--(ro-)?bind[^\n]*(PI_MCP_SESSION_HOME|PI_MCP_RUN_DIR)/);
});

test('the jail gets a tmpfs /tmp and no workspace or home mount', () => {
  assert.match(forms, /--tmpfs \/tmp/);
  assert.doesNotMatch(forms, /--(ro-)?bind[^\n]*\/workspace\//);
});

test('each form consumes exactly one positional and forwards the rest with no executable word and no `--`', () => {
  assert.match(forms, /session_dir=\$1/);
  assert.match(forms, /^\s*shift\b/m);
  assert.match(forms, /exec \$\{jail\}\/bin\/jailed-\$\{name\} "\$@"$/m);
  // No second positional, and nothing appended to the forwarded argv.
  assert.doesNotMatch(forms, /\$2\b/);
  assert.doesNotMatch(forms, /exec [^\n]*"\$@"[^\n]*--/);
});

test('the flake carries the bind-set probes and the check that reads the built launchers', () => {
  const probes = region(flake, 'jailProbes = {', 'launcherCheck =');
  assert.match(probes, /pi-mcp = \{/);
  assert.match(probes, /read = \{/);
  assert.match(probes, /write = \{/);
  // The expected residue over the generator's own jail is root + session
  // directory; the generator's binds are derived from a baseline built by the
  // same call, never listed, so a generator change cannot fail or move it.
  assert.doesNotMatch(probes, /shared = \[/);
  assert.match(flake, /piMcpJail = /);
  assert.match(flake, /piMcpBaseline = piMcpJail /);
  assert.match(flake, /piMcpFormCheck = let/);
  assert.match(flake, /pi-mcp-forms = piMcpFormCheck;/);
});
