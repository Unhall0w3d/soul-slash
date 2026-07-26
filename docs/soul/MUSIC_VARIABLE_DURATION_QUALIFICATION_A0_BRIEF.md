# Music Variable-Duration Qualification A0 Brief

## Objective

Qualify bounded, exact music durations before deciding whether Soul's production
Music Studio should accept a continuous duration range instead of only fixed
presets.

The first creative study is a five-part, original liminal-environment sequence:
a short threshold, two full movements, and two shorter interludes. The pieces
share tonal material, environmental texture, and transition tails so a future
mix editor can assemble them without abrupt stylistic breaks.

## Boundary

- The implementation candidate accepts any exact whole-second Music Studio
  duration from 30 through 300 plus the fixed 600-second option. It remains
  unmerged until human review.
- The foreground Vulkan pilot may accept any exact whole-second duration from
  30 through 300 seconds only when the request contains
  `variable_duration_v1`. For example, 2:24 is represented as 144 seconds.
- Ten minutes remains the separately reviewed 600-second production preset; the
  qualification range does not create a 301–599-second lane.
- Existing fixed pilot durations remain unmarked. The historical 210-second
  qualification remains reproducible with `duration_210_v1`; new continuous
  qualification may also address 210 seconds with `variable_duration_v1`.
- A variable marker cannot be attached to an existing fixed pilot duration.
- One output, batch size 1, eight inference steps, VAE chunk 256, no offload,
  three bounded LM-plan attempts, exact preview digest, and
  `RUN_MUSIC_VULKAN_PILOT` confirmation remain unchanged.
- Execution is foreground and bounded. No service, queue, daemon, listener,
  watcher, scheduler, or automatic production promotion is added.
- Pilot audio remains local qualification evidence. Human listening review is
  required before merge even when deterministic checks pass.

## Creative study

The five-piece sequence uses instrumental ambient techno, deep-house, and
atmospheric breakbeat language inside a fluorescent liminal-office sound world.
All pieces remain original. Sparse non-lexical breath or choir texture may
appear in the intro or interludes, but no lyrical text is supplied.

Visual companions are separate native text-to-video briefs. They share a locked
yellow-green fluorescent palette, dark thresholds, analog surveillance texture,
and restrained camera movement. Each remains an ungenerated project until its
ordinary exact render gate is approved.

## Acceptance

Technical acceptance requires representative short and long non-preset pilots
to:

- produce exactly one non-empty 48 kHz stereo WAV within two seconds of the
  requested duration;
- pass the existing audio-code collapse guard;
- exit within the existing bounded timeout with no resident process;
- retain request, log, digest, runtime, and duration evidence;
- leave production duration validation unchanged.

Human review must later assess musical coherence, transition usefulness,
repetition, natural endings, and whether the duration range deserves production
promotion.

## Risk

Risk classification: local compute and temporary storage, medium. Variable
durations increase the number of runtime shapes that can be requested, but the
qualification marker, exact gate, whole-second range, retries, and timeouts
remain bounded.
