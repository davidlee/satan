# SATAN

**Scheduled Agent for Textual Attention and Notes**

![SATAN](./gnu3.png)

SATAN is an experiment in a personal agent with memory, motives, and something
to notice. It reads my notes and recent activity, asks inconvenient questions,
offers interventions, and proposes changes to its own code and persona. The
aim is continuity: an agent whose next interaction has some relationship to
what happened last time, and whether it helped.

It began inside my [Emacs configuration](https://github.com/davidlee/emacs-config).
It has since grown into a small system of cooperating programs. This repository
holds the Emacs Lisp broker, its tools and perception/memory machinery, and the
subprocess harness used by broker-driven runs. Other repositories supply
activity capture, durable conversations, behavioural attributes, and confined
code execution. [Nix](https://github.com/davidlee/nix-config/tree/main/flakes)
assembles them into a working environment.

## The pieces

| Project | Part in the system |
|---|---|
| **SATAN** — this repo | Assembles context, resolves modes and permissions, dispatches tools, records runs and interventions, and exposes tools over MCP. The broker currently runs inside Emacs. |
| [**emacs-config**](https://github.com/davidlee/emacs-config) — `~/.config/emacs` | Loads SATAN and connects it to my Org/Denote workflow. Emacs provides the human interfaces for inspecting runs, reviewing proposals, and promoting or rejecting patch jobs. It can also attach to Malebolge. |
| [**nix-config**](https://github.com/davidlee/nix-config/tree/main/flakes) — `~/flakes` | Composes packages, services, timers, jail profiles, databases, and the LiteLLM gateway that brokers model access and provider credentials. This is where the components become a deployment. |
| [**Panopticon**](https://github.com/davidlee/panopticon) | Records desktop, Firefox, and Git activity, including readable page captures. Runs independently of Emacs; SATAN reads its local files through tools and perception code. |
| [**Malebolge**](https://github.com/davidlee/malebolge) | Hosts durable agent conversations using pi-durable. Ships the interactive daemon and the separate **`satan-runner`** patch-job daemon, each with its own SQLite store. |
| [**Oubliette**](https://github.com/davidlee/oubliette) | Provides microVM capsules and persistent rooms. The patch runner's coding tools execute in a room; committed work returns through a host-controlled Git channel into quarantine. |
| [**satan-attrd**](https://github.com/davidlee/satan-attrd) | Rust daemon maintaining behavioural attributes, their event history, and decay in Postgres. Consumes outcome and other supported signals; the broker reads the resulting attribute context. |
| [**goad**](https://github.com/davidlee/goad) | A desktop surface for intervention and interrogation: nudges, questions, and answers that can help test SATAN's hypotheses about what is happening. Its SATAN-specific backend lives in the corpus. |

The persona has its own home, too: `~/satan-corpus` contains prompts, framing,
tool descriptions, motives, and the hippocampus. Keeping this separate lets
SATAN propose changes to how it thinks independently of changes to its mechanism.

## From observation to action

Panopticon supplies evidence of where attention went: applications, pages,
projects, and commits. Notes supply intentions and personal context. SATAN
builds a compact percept, recalls relevant memory, reads its current motives
and attributes, and gives a model the context and tools allowed by the mode.

A run might notice an unresolved intention, inspect recent project activity,
ask a question through goad, or leave a proposal in its inbox. Observations and
interventions can become memory traces. Classified outcomes feed the attribute
layer, so later context can reflect an intervention that worked, was ignored,
or was contradicted. Activity is evidence to interpret; window focus alone
does not establish what someone understood or accomplished.

Goad lets SATAN ask about the gap between observation and interpretation. A
long stretch of browsing might be research, avoidance, or a break. A question
such as “Are you looking for something specific, or stuck choosing what to do?”
can supply evidence for or against that interpretation, as well as prompt a
change of direction. This is the intended loop: form a hypothesis, ask or
intervene, then revise it in light of the answer and subsequent activity.

```text
 notes + corpus + memory       Panopticon activity
              \                    /
               v                  v
                   SATAN broker (Emacs)
                    /             \
       scheduled/manual runs       MCP tools
            jailed harness         Malebolge conversation
                    \             /
                questions, proposals, interventions
                           |
                    outcomes + memory
                           |
                      satan-attrd
                           |
                  later attribute context

 patch request -> satan-runner -> Oubliette room
                                      |
                                  commits
                                      v
 real repo <- human promotion <- host quarantine

 model clients -> LiteLLM gateway (nix-config) -> providers
```

There are currently two ways of talking to models. Broker-driven modes such
as morning and tick runs launch a bounded subprocess harness. Malebolge holds
an ongoing conversation that clients can attach to and leave without owning
its lifetime; it reaches SATAN's tools over the Emacs MCP socket.

The harness ecosystem includes:

- [**gptel**](https://github.com/karthink/gptel) — the Emacs-native chat and
  tool-use interface in the editor configuration. SATAN's scheduled subprocess
  is still named `satan-gptel-harness`, though its current implementation is a
  Python chat-completions loop speaking SATAN's JSONL protocol.
- [**pi**](https://pi.dev/) — the interactive coding-agent harness; a SATAN
  extension connects it to the broker's tools over MCP.
- [**pi-durable**](https://github.com/earendil-works/pi/tree/main/packages/durable)
  — the durable harness library beneath Malebolge's interactive daemon and
  patch runner, allowing conversations and jobs to survive their clients.

The harness supplies the model/tool loop; SATAN supplies the personal context,
memory, motives, and capability policy around it.

**The host LiteLLM gateway brokers credentials and model access.** Provider
keys stay with the gateway. SATAN's harness and Malebolge use gateway client
credentials with model allowlists and spending limits, rather than receiving
provider keys. The patch runner keeps provider credentials out of its Oubliette
room as well: its model loop runs on the host, while the room executes tools.
Nix configures the gateway and credential delivery alongside the jail profiles.
See the [gateway documentation](https://github.com/davidlee/nix-config/blob/main/flakes/README.md#llm-gateway)
for its client contract and operations.

## Changing itself

SATAN can submit a patch job against a configured repository, including its
mechanism or corpus. **`satan-runner`, from Malebolge, owns that job end to end:**
admission, queue, durable conversation, ceilings, recovery, and collection.
The model loop lives on the host; coding tools run inside an Oubliette room.

The runner collects committed work into quarantine and checks ancestry and
allowed paths. Reviewable results appear in Emacs. Promotion creates a branch
at the reviewed commit; merging is a further human decision. The room does
not directly edit the real checkout. See [Malebolge's patch-job
guide](https://github.com/davidlee/malebolge#patch-jobs) for the workflow.

## Memory, temperament, and authority

There is a family resemblance to an **LLM Tamagotchi**: a persistent persona,
visible attributes, and a little creature whose state changes over time. The
comparison is useful, but the care loop points outward. Hunger is pressure
toward contact and progress in the user's world; Curiosity is pressure to seek
evidence; Doubt should temper certainty; Metamorphosis is pressure to propose
self-change. The experiment is whether those variables help an agent attend,
question, and intervene usefully. Keeping its meters satisfied is not the goal.

The attributes are named Curiosity, Hunger, Suspicion, Doubt, Cruelty, Shame,
Brooding, and Metamorphosis. They are explicit control variables supplied as
behavioural context, with mechanical update rules and decay. Their wiring is
uneven; the names describe the experiment's vocabulary, not eight complete
psychological faculties. [The wiring notes](docs/attributes/wiring-status.md)
describe which signals drive them.

**Attributes bias behaviour; they never expand permissions.** Mode scopes,
tool validation, budgets, audit records, and approval surfaces are separate
mechanisms. Confinement and the tool protocol both matter: access to an MCP
socket or a writable host mount is itself authority. The system is personal
research infrastructure, with ongoing boundary and deployment work.

Ownership of the text is similarly explicit:

| Root | Purpose |
|---|---|
| `~/notes` | My notes. The broker's note-reading tools treat these as read-only. |
| `~/satan-corpus` | SATAN's versioned, model-facing material: persona, prompts, motives, hippocampus, and proposals. |
| `~/.local/state/satan` | Runtime files and run history. Malebolge also keeps its durable conversation and runner stores here; preserve those to retain continuity. |

Panopticon owns its separate activity store under `~/.local/state/behaviour`.
Postgres holds SATAN's structured memory, interventions, and attributes.

## Where this is going

The direction is an agent whose lifetime is independent of its editor clients,
with coding work confined to a room and host effects exposed through explicit
capabilities. Emacs keeps the human approval surfaces. Extraction follows a
simple question: does this component use the editor *as an editor*?

The split is still in progress. The broker and many tools remain Elisp;
attributes and patch-job lifecycle already live outside Emacs. Scheduled modes
have not yet become events in one durable conversation. Malebolge's interactive
execution is also being moved toward the room model; the patch runner already
uses it. The [system map](.doctrine/spec/tech/002/spec-002.md) distinguishes the
current topology from the architectural destination.

## Finding your way around

- [Documentation index](docs/INDEX.md) — broker architecture, protocol, perception, memory, and attributes.
- [Whole-system map](.doctrine/spec/tech/002/spec-002.md) — containers, transports, composition invariants, and links to diagrams. `doctrine spec show SPEC-002` includes its requirements.
- [Deployment notes in nix-config](https://github.com/davidlee/nix-config/blob/main/flakes/SATAN.md) — host paths, units, jails, pins, and operational details.
- [Malebolge](https://github.com/davidlee/malebolge) — interactive clients and the current patch runner.
- [Oubliette](https://github.com/davidlee/oubliette) — rooms, confinement, and Git transfer.

For development, enter the Nix devshell, then run:

```sh
just db-start    # local Supabase; run outside a jail
just db-setup    # create the test databases
just check      # lint + interpreted Elisp, Python, and Luau tests
```

The Elisp package requires Emacs 30.1 or later. A full agent deployment also
needs the corpus, gateway, services, and confinement configuration described
above; loading the package alone does not assemble them.
