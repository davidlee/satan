An unjailed process inside a jail is jailed, and a jailed process inside a
jailed process carries the union of both jails' restrictions. Read that as an
INTERSECTION of permitted authority, not as "nesting never narrows":

- An inner mount namespace CAN narrow further — an inner `--ro-bind` over a rw
  bind, or a masked path, strictly reduces what the process may do.
- An inner jail can never WIDEN what the outer one allows.
- Authority that the mount namespace does not govern survives nesting:
  inherited file descriptors, credentials, and reachable services (a socket a
  parent opened) remain usable inside. A nested jail is therefore not a proof
  of reduced authority; it is a proof about filesystem visibility only.

Earlier text in this record said "additive, never narrowing", which was a wrong
transcription: it contradicted the first sentence and misled a design decision
(DEC-089 consequence 2). Corrected 2026-10-20 after an external review; the
useful question is which capabilities survive this particular nesting.
