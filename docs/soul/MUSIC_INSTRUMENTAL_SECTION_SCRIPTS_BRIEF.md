# Instrumental Section-Script Experiment — Superseded

This brief is retained as historical evidence. The marker-only instrumental experiment was superseded after checking the pinned `acestep.cpp` runtime contract.

The pinned runtime has no `instrumental` boolean. Its lyrics field is the single source of truth:

- empty lyrics asks the LM to generate lyrics;
- exact `[Instrumental]` selects the trained no-vocal condition;
- every other value is treated as user-provided lyrical conditioning.

Soul therefore stores an instrumental project with an empty human lyrics field but sends exact `[Instrumental]` in the generation input. Instrumental structure must be expressed as a concise broad progression in Sound and Structure; bracketed temporal scripts remain available to vocal projects.

The experiment did not weaken an authorization gate or start unattended work. Its deterministic tests were replaced by runtime-alignment tests.
