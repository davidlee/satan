SL-029's audit cross-checked every member of the `pi-mcp-forms` probe list
against the jail generator and concluded "all members match, so a red check is a
real defect". The conclusion held, but the assurance was wrong in kind. The
check asserts **set equality**, and the first real run went red on eight
jail.nix base/network binds the list never named (RV-055 F-6). Checking each
member proves *membership*; equality also needs *completeness*.

**How to apply:** when auditing an equality assertion against a reference
(probe lists, allowlists, schema field sets, expected bind sets), get the
**actual** set from the real artefact (build it, dump it) and diff both ways.
Do not reason from the expectation outward. If the actual set cannot be produced
where you are, say the completeness half is unverified rather than certifying the
check. Related: [[mem.pattern.nix.text-probe-flake-check-silent-pass]] (a probe also
has to be shown to fail).
