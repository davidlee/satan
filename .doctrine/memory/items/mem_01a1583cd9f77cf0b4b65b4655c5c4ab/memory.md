# Jail policy lives in the flake and is exposed as a wrapped form

Jail policy is project-specific: it belongs in the project's flake, which wraps execution and exposes a wrapped form (jailed-pi, jailed-claude). A tool or server should exec that wrapper and hold no bwrap argv of its own; a consumer that reimplements confinement is a second enforcement site (REQ-009).
