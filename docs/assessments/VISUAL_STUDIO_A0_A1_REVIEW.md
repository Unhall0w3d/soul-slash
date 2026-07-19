# Visual Studio A0–A1 Candidate Review

## Candidate status

`candidate_complete` pending owner dashboard and image review.

## Implementation summary

- Grouped Music Studio and Visual Studio beneath **Creative Studios**.
- Added a private project archive, visual brief, exact generation preview, click
  authorization, bounded render progress, and retained candidate gallery.
- Added pinned `stable-diffusion.cpp` Vulkan setup and exact model download gates.
- Installed the host runtime and verified 5,207,178,964 bytes of model files.
- Ran a live 1024×576 FLUX.2 Klein draft through the application service.
- Kept the LTX-Video motion lane visibly unavailable pending AMD qualification.

## Files changed

See the candidate commit. Primary additions are:

```text
config/visual_studio_models.json
lib/soul_core/visual_studio_service.rb
scripts/soul-visual-runtime
scripts/verify-visual-studio-a1.rb
docs/soul/VISUAL_STUDIO_A0_A1_BRIEF.md
assets/dashboard/index.html
assets/dashboard/dashboard.js
assets/dashboard/dashboard.css
```

## Host evidence

```text
Runtime revision: ea4e566ccffa10f853ecc3f29e74b1820bc91beb
Profile: FLUX.2 Klein 4B Q4
Accelerator: AMD Vulkan
Exact model bytes: 5,207,178,964
Pilot project: First Light Calibration
Pilot resolution: 1024×576
Pilot elapsed time: 9.885 seconds
Pilot SHA-256: ba7d9e51bc11b07a416a1c450a463840ff34e9e30681152d50302de5eb1c3bd2
Terminal state: blocked_for_human_review
```

## Deterministic test results

```text
ruby scripts/verify-visual-studio-a1.rb — PASS (12 checks)
ruby scripts/verify-dashboard-self-improvement-navigation.rb — PASS
ruby scripts/verify-music-studio-a3.rb — PASS
ruby scripts/verify-music-visual-companion.rb — PASS
ruby -c scripts/soul-visual-runtime — PASS
ruby -c lib/soul_core/visual_studio_service.rb — PASS
node --check assets/dashboard/dashboard.js — PASS
git diff --check — PASS
```

The Phase 12B and Phase 13 wrappers initially reached the expected repository
curation block while this new verifier was untracked. After intentional staging,
both full wrappers passed, including the updated primary navigation contract.

## Local LLM eval results

Not run. This slice concerns filesystem integrity, exact approvals, process
termination, GPU execution, artifact validation, and dashboard transport. An LLM
cannot certify those properties.

## Memory keys

None read, created, or updated.

## Lifecycle states touched

`complete`, `awaiting_input`, `failed`, `blocked_for_human_review`.

## Risk classification

Medium local resource and filesystem mutation. One user-approved ~5.2 GB model
download and one compiled local runtime were added outside Git. No privileged
mutation, listener, service, scheduler, or unattended process was added.

## Known weaknesses

- Still-image review disposition, deletion, iteration/edit input, and explicit
  Music Studio promotion remain later vertical slices.
- The first resource inspection hashes 5.2 GB of model data and can take several
  seconds; later work may add a signed/stat-bound local verification receipt.
- Motion remains unqualified. The UI states this rather than substituting an
  unproven runtime.
- Visual jobs use the bounded streaming request path but do not yet use Music
  Studio's refresh-resilient detached job ledger.

## Safety and persistence check

```text
Persistent service added: no
Daemon/listener added: no
Watcher/scheduler added: no
Background continuation added: no
Confirmation gate weakened: no
Private memory store added: no
Automatic Music Studio promotion: no
```

## Human review checklist

```text
[ ] Creative Studios navigation is clear and retains Music Studio parity
[ ] Visual project form and first candidate render correctly
[ ] Candidate quality is sufficient to keep iterating on this model lane
[ ] Motion is clearly shown as unavailable/qualification pending
[ ] Exact approval and private storage boundaries are acceptable
```
