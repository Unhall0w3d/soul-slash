# AMD reviewer M3B — model substitution comparison

2026-10-13. The current user asks to explore new AMD test models and test whether
changing the model helps. This authorizes public model downloads and detached,
bounded comparisons, not production promotion, services, LoRA, private-data
transfer, memory writes or LibreChat delivery. M4 integration remains separate.

## Fixed comparison

Compare cached Ministral3-14B Q4_K_M against public Qwen3.5-9B Q4_K_M and
Microsoft Phi-4-14B Q4_K_S. The new artifacts are revision/size/SHA256 pinned in
`scripts/support/amd_reviewer_assets_m3b.json`, downloaded without credentials
to `/home/bhones/ai_models/amd-reviewer-m3b`. Retain partials on failure. These
are roughly 14.61 GB total disk writes; no model is registered as a default.
Available disk was 609 GiB. No packages or inference runtimes are installed.

Use the installed Vulkan server and each model's native embedded template.
Qwen3.5 thinking is explicitly disabled with `enable_thinking:false`; this is
a short-response reviewer comparison, not a qualification of extended reasoning.
No multimodal projector is needed for these text-only packets. Standard Phi-4
is selected instead of reasoning-plus to avoid silently starving a reasoning
model with the existing short-generation budget. Public cards inform selection,
not a claim of local quality or compatibility.

For each model, reuse the exact ten immutable original Qwen answers from the
successful M3 v2 receipt, not regenerated or corrected answers. For each source:
review, then independently ask resident Qwen to revise using the attributed,
unendorsed review. Also run the ten old seeded reviews and eight fresh held-out
seeded reviews (two each supported, contradicted, insufficient and mixed).
Finally, for each original, ask Qwen to reconsider without a review. Each branch
starts from its own original and supplied evidence; none consumes another branch.
The control is repeated per candidate to expose execution variation. Forty-eight
generations maximum per model, 144 across three explicitly initiated windows.
Rotate case order across model windows. Do not rerun for unfavorable quality.

Freeze fixtures, source answer hashes, prompts, scorer, model/runtime/source
hashes before inference. Retain old M3 scores unmodified. Existing cases are
regressions, not held-outs. Newly authored eight cases are held-out review-only,
not evidence of applied correction. Do not send oracle/seed labels to inference.
Same rubric, strict schema and exact-answer scorer as M3. Explicitly pin presence
and frequency penalties to zero for both models, eliminating M3's inherited
Qwen presence-penalty mismatch. Pin dry multiplier zero, mirostat off, typical-p
one, alongside the prior sampler. Verify returned effective sampling settings.
Context 4096; input <=3072; output <=768. Native templates differ by model.

## Interpretation and limits

Report old seed and fresh seed verdict accuracy separately, category confusion,
unsupported-versus-contradicted errors, supported false criticism, correction and
spoilage relative to the same originals and no-review control, latency, token
cost, load/teardown and thermals. Inspect findings semantically: schema validity
or correct verdict does not prove evidence grounding. Compare complete paired
cases; interrupted or invalid runs remain distinct and cannot become successes.
A useful candidate should reduce calibration errors without spurious criticism
and yield net useful corrections beyond the no-review control. Small synthetic
results justify a next qualification, not general superiority or promotion.

## Lifecycle and checks

Keep M1, Continuity, M2 and M3 source untouched. Primary owns new runtime harness,
download route, authority and closeout. Luna may own fresh fixtures/tests; Sol
may research and critique read-only. Preserve unrelated dirty work.
Reuse M3's AMD gate, own-child cleanup, exclusive lease/control lock, authenticated
loopback 8096, Qwen identity/idle checks, 3-second minimum cooldown (resume <=55 C
edge/70 C junction within 30 seconds), batch128/microbatch32, v1 abort at80/95 C
(superseded for new v2 windows by the explicit authorization below),
>=2GiB VRAM free, >=8GiB RAM free and swap/log limits. NVIDIA Qwen remains resident
unchanged. Admission failure means unavailable, not eviction or fallback. Every
window <=1800 seconds; AMD calls <=90 seconds; Qwen <=60; startup <=180. No daemon,
automatic retries, watcher or background continuation. A loader incompatibility
is a runtime result, not a quality score. Finish other independent candidates
after verified cleanup; a thermal abort ends live work for this turn.

Before live: pinned Ruby4.0.7 syntax, fresh-fixture verifier, runner boundary tests,
inherited M2/M3 lifecycle verifiers and changed-path check routing. Focused review
of model substitution, native-template handling, evidence isolation and teardown.
After: source/config/runtime hashes and Qwen PID unchanged, idle primary, 8096
closed, owned AMD child reaped, VRAM released, own lease gone. Update assessment
and canonical review indexes with deterministic/live/semantic evidence separate.

## V2 thermal envelope — explicitly authorized 2026-10-13

The operator approved proceeding and expressly selected100C junction as their
personal cutoff, accepting the preceding proposed90C edge/90C memory guardrails.
For new v2 windows abort at **edge>=90C, junction>=100C or memory>=90C**, sampled
every0.5 seconds. The original v1 aborted at80C edge/90C junction on request48;
its47 complete responses, partial final request and original runner/brief copies
remain retained. This is a fresh experiment, not a rescoring or continuation.
Exactly one new bounded48-call window per declared model (maximum144 new calls).
All other resource, context, token, timeout, cooldown, lease and cleanup bounds
remain unchanged. Do not modify LACT, power/fan/clock/voltage, BIOS or RAM tuning.
Capture applied core-clock, voltage, power and driver thermal limits before/after
each window. A change is reported as a preservation failure, not silently accepted.

The applied2400MHz core cap/zero voltage offset/281W cap were read back. Fan curve
to100% at75C, Thermaltake P5/cool basement and RAM tuning are operator-reported.
Their supplied dmidecode shows configured3800MT/s; this corresponds to1900MHz
MCLK, and would imply1900MHz FCLK at the reported1:1 ratio, not direct FCLK
measurement. All settings remain untouched. Stock/undervolt/underclock/combined
performance and power comparisons are expressly deferred until after LibreChat.

Seven newly authored review-only outputs were observed in the v1 partial run;
the unchanged eight-case set is therefore a retained challenge set/retest, not
eight wholly unseen held-outs. No prompt, case, scorer or model tuning is based
on those results. The old parcel/custodian fixture has an unstated identity join;
retain its frozen score but flag the ambiguity and show sensitivity without that
case when interpreting useful correction or false criticism.
