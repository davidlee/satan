# DEC-056: SL-023 runner schedules one job at a time, FIFO, woken by submit; policy ladder and prompt composition ported

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


Revised 2026-10-18 during drafting, user direction: pi-durable's Harness.open does not resume work; resume(), a submit or a wait starts the task scheduler (pi-durable README, Storage). Startup therefore runs the recovery table before resume(), and a disabled runner never resumes.