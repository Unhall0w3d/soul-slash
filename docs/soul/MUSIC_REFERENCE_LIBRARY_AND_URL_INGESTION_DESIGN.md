# Music reference library and URL ingestion design

## Approved outcome

Music Studio may turn an Operator-supplied song URL into a private, local,
reviewable reference profile. A profile separates source provenance, observed
musical evidence, and Soul's proposed composition material. Approved profiles
may be selected individually or fused into a coherent new composition brief.

This capability is available through the dashboard and, in a later slice,
through the same bounded Music Studio skills used by conversation.

## Copyright, rights, and originality boundary

- URL analysis begins in `analysis_only` mode. It may transiently decode one
  source for feature extraction, but it does not retain the source audio or a
  full source transcription after the foreground operation terminates.
- The retained profile contains provenance and non-expressive derived evidence:
  tempo/key candidates, meter likelihood, arrangement and section topology,
  instrumentation, production traits, energy/dynamics, vocal delivery traits,
  themes, diction tendencies, rhyme/meter tendencies, and confidence notes.
- The retained lyrical profile must not contain copied source lyrics. Generated
  lyrics and section markers must be newly drafted material.
- `owned`, `licensed`, and `public_domain` are Operator assertions, not findings
  Soul can infer or certify. They may authorize later operation-specific source
  retention; this design does not implement that retention.
- Artist and song names remain in local provenance and review UI. Generation
  input uses the derived traits, omits artist names, and includes explicit
  originality/exclusion guidance.
- Soul cannot certify originality, copyright status, permission, or release
  readiness. Every generated packet and song remains a human-review candidate.

## Layered record model

Reference data is project-domain state under the ignored `Soul/music/references`
root, not skill-private personality memory.

1. **Provenance** — canonical URL, source platform and ID, source title, credited
   artists, album/release when confidently known, duration, rights assertion,
   tool versions, timestamps, and optional MusicBrainz identifiers.
2. **Observed evidence** — measurements and confidence for BPM, key/scale,
   meter, dynamics, sections, instrumentation, mix/production, vocal delivery,
   and non-expressive lyrical traits.
3. **Composition synthesis** — a versioned, editable proposal containing intent,
   a new title, Sound and Structure, new lyrics and section markers, target BPM,
   target key, time signature, exclusions, and rationale.

Observed source values are not regenerated. “Try again” creates a new immutable
synthesis revision for either the whole packet or one component. A key retry
therefore proposes a different compatible target key; it does not revise the
measured source key.

## Library hierarchy and fusion

The dashboard presents Artists → Albums → Tracks, plus reviewed Fusions. Album
grouping is used only when metadata is sufficiently confident; otherwise tracks
remain under an “Unresolved release” group. Manual correction is reviewable and
does not rewrite the original provider evidence.

A fusion is a first-class, versioned synthesis derived from two to five selected
profiles. It records each source's role and weight, compatibility decisions,
conflicts, and the resulting unified traits. Soul must synthesize a coherent
hybrid (for example, a funk rhythmic language within a pop song architecture),
not concatenate or simultaneously overlay unrelated prompts. Fusion output is
reviewed before it can seed a new composition.

## Bounded URL operation

The first URL provider is YouTube only. Accepted hosts are canonical HTTPS
`youtube.com`, `www.youtube.com`, `music.youtube.com`, and `youtu.be`; one video
is permitted and playlists are rejected. Other providers require a later review.

The foreground operation has two gates:

1. Metadata preview performs no media download and returns canonical identity,
   duration, proposed storage scope, dependencies, limits, and a digest.
2. Execution requires `ANALYZE_MUSIC_REFERENCE` and that exact digest.

Execution uses `yt-dlp --ignore-config --no-playlist` without cookies,
authentication, external downloaders, or execution hooks. Limits are one URL,
15 minutes duration, 250 MiB transfer, bounded output, fixed timeouts, and finite
retries. FFmpeg creates temporary analysis copies. Plain Essentia supplies basic
audio descriptors; a separately pinned Essentia TensorFlow environment supplies
fallible genre, mood/theme, instrumentation, voice-presence, and structural-change
evidence. When voice is likely, the existing transient whisper.cpp lane derives
non-expressive lyrical traits. Source audio and raw machine transcription may
exist only inside the operation's private temporary directory and are removed on
every terminal outcome. Optional MusicBrainz enrichment is bounded and ambiguous
matches require Operator selection.

All subprocesses belong to the request and terminate on success, failure,
cancellation, timeout, client abandonment, or dashboard shutdown. Temporary
media and raw source transcription are removed at every terminal outcome in
`analysis_only` mode. There is no queue, watcher, resident model, scheduler,
automatic retry after return, or background continuation.

New references use one exact-gated foreground operation and one source download
to collect both basic and rich evidence. Legacy profiles that lack versioned
semantic evidence expose `REANALYZE_MUSIC_REFERENCE`; reanalysis redownloads the
source transiently and replaces only observed evidence. It is blocked when an
approved synthesis or fusion depends on the current evidence.

One selected track profile may be permanently removed with a fresh digest-bound
preview and `DELETE_MUSIC_REFERENCE`. The operation is blocked while a fusion
depends on that track. Artist and album groupings are derived from remaining
tracks, so an empty grouping disappears automatically. No source media is retained
or deleted because it was already removed at analysis completion.

## Lifecycle

Each operation terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`. Successful analysis returns
`blocked_for_human_review` until the Operator accepts or edits the synthesis.

## Delivery slices

### A5.1 — reference-library foundation

- Add deterministic, private reference storage and schema validation.
- Add read-only inventory operations and a three-column Music Studio library
  surface with Artists, Albums, Tracks, and Fusions.
- Seed no data and perform no network or model work.
- Provide a disabled/explicitly pending URL intake surface so the next boundary
  is visible without implying analysis already works.

### A5.2 — bounded YouTube evidence

- Add metadata preview and exact-confirmation foreground execution.
- Add pinned optional setup/checks for yt-dlp, plain Essentia, the isolated
  Essentia TensorFlow classifier set, and transient whisper.cpp.
- Extract, validate, and retain provenance plus non-expressive evidence; remove
  transient media and raw transcription.
- Collect basic and rich evidence in the same user-facing operation; expose a
  separately exact-gated reanalysis path for incomplete legacy profiles.

### A5.3 — synthesis, retry, and fusion

- Add Soul-generated synthesis candidates with whole-packet and component retry.
- Preserve immutable revisions and distinguish observed values from targets.
- Add album/artist aggregation, multi-profile fusion, and human approval.

#### A5.3 bounded behavior

- Synthesis uses one configured local provider request with a 90-second timeout,
  strict structured output, no tools, and no cloud-provider fallback.
- A first synthesis must use scope `all`. Later retries may use `all`, `intent`,
  `title`, `caption`, `lyrics`, `bpm`, `keyscale`, or `timesignature`.
- Component retry supplies the complete current packet for coherence but code
  preserves every non-requested component byte-for-byte. Every attempt receives
  an immutable `syn_` revision ID; revisions are never overwritten.
- Source titles, credited artists, albums, channels, and other identity metadata
  are withheld from synthesis. The model receives only bounded duration plus
  reviewed semantic evidence; it receives no source audio, raw extractor receipt,
  or raw source transcription. Stored Sound and Structure and generated lyrics
  must not request imitation or reproduce source lyrics.
- Synthesis fails closed unless the evidence carries a versioned semantic
  enrichment receipt and non-empty section, instrumentation, production, energy,
  and vocal observations. Tempo/key plus raw extractor scalars are insufficient.
- Drafting terminates `blocked_for_human_review`. Approval requires an exact
  preview digest plus `APPROVE_MUSIC_REFERENCE_SYNTHESIS`; only that operation
  sets the selected revision and makes a reference eligible for fusion.
- Fusion accepts two to five approved track references. Soul receives their
  selected derived packets without artist names and must assign a clear role and
  weight to every source, reconcile conflicts, and return one unified packet.
  Prompt concatenation, automatic generation, and automatic profile approval are
  prohibited.

#### A5.3 acceptance criteria

- Invalid/local-cloud providers, malformed JSON, Markdown-wrapped JSON, missing
  evidence, and unchanged retry output fail before any approval mutation.
- Whole and component retries append immutable revisions; component retries
  cannot alter unrequested fields.
- Approval is digest-bound, exact-confirmed, idempotent, and never approves a
  different revision.
- Rejection is independently digest-bound and exact-confirmed, preserves the
  immutable revision, prevents its later approval, and leaves the profile
  available for a new candidate retry.
- Fusion rejects unapproved, duplicate, missing, fewer-than-two, or more-than-five
  sources and stores roles/weights alongside its candidate synthesis.
- Dashboard views visibly separate observed source evidence from proposed target
  material and expose no automatic retry, approval, fusion, or generation.

### A5.4 — composition and conversation bridge

- Seed the composition form from one or more approved references or fusions.
- Add the bounded `music.compose` conversation workflow and title suggestion.
- Preserve exact final-readout confirmation before project creation/generation.

## A5.1 acceptance criteria

- No reference path can escape the repository-local ignored root or traverse a
  symlink.
- Every stored record has an exact schema, bounded fields, stable identity,
  timestamps, provenance, rights assertion, and lifecycle/review status.
- Inventory is bounded and groups tracks under artists and albums without
  inferring missing metadata.
- The dashboard renders an empty reference library on desktop and collapses it
  beneath the workbench on narrow screens.
- A5.1 adds no downloader, network request, model call, service, queue, timer,
  polling loop, automatic source retention, or generation mutation.
