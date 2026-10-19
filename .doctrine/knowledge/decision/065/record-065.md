# DEC-065: SL-023 room adapter and door kind behind the existing ports, built against oubliette SL-006 fixtures

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->



Revised 2026-10-19 (oubliette SL-006 RV-018 relay; user: 'sure'): room reachability is the job's own collect, bounded by transfer_timeout_s; capsule <room> ssh <user> true is never a probe (it reads a changed host key as downtime). Collect stdout <oid>\t<ref> pinned by oubliette and cross-checked.



Revised 2026-10-19 at SL-023 reconcile (RV-029 F-5, F-8; user ruling (1) of 2026-10-19): the slot is no longer the live rung — the closure run (P promoted, R rejected) ran against the deployed room door (`[door] kind = "room"`, room `assistant`), and PHASE-12 plus the closure run cover the live room rung; the ruling waived the silence-limit drop, the oubliette verbs' host-key refusal and the agent-home check. The re-check against oubliette SL-006 at its lock is done (RV-029 F-7: SL-006 done, last design change ad2dd7d, every runner-facing change implemented). Room config values are literals in ~/flakes, each commented with its fleet source, because the fleet exposes no room data to the standalone home-manager config; one source at Nix eval waits on a fleet output, and the preparing guest_path check and push oid gate catch drift.