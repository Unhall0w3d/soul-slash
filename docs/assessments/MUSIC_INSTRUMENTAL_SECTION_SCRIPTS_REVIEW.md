# Instrumental Section-Script Experiment Review

Status: superseded by pinned-runtime evidence

The implementation originally preserved bracket-only scripts for instrumental projects. Listening showed that the tags influenced structure, but the pinned C++ runtime documents only exact `[Instrumental]` as its trained no-vocal condition. Arbitrary marker text is user-provided lyrical conditioning even when the caption says “no vocals.”

The implementation was removed before further production use. Soul now:

- keeps the human lyrics field empty for instrumental projects;
- sends exact `[Instrumental]` to the LM and synthesizer;
- maps instrumental vocal language to `unknown`;
- rejects instrumental lyrics or section markers at project creation;
- keeps vocal structure tags concise and separate from the overall caption.

No memory keys or persistent processes were added. Existing exact generation and listening gates remain unchanged.
