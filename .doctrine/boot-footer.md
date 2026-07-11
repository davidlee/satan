<!-- Seeded once by `doctrine install`; YOURS to edit.
     Injected as `## Onboarding` at the end of the boot snapshot
     (just before `## Invoking doctrine`), so every agent session
     sees these instructions.

     Use it to tell agents to read specific memories, or anything 
     else they should do on every session start.
     Keep it short. -->

Immediately on beginning your NEXT TURN:
If the MCP `doctrine_onboard` tool is available, call it to get onboarding context
in a single call. Otherwise, use /retrieving-memory skill to retrieve
`mem.signpost.doctrine.overview` and `mem.signpost.project.orientation`.

