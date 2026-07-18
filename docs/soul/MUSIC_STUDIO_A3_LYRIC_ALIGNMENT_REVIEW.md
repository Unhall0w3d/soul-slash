# Music Studio A3 repeated-section alignment review

## Candidate status

`candidate_complete` — awaiting Operator review.

## Implementation summary

The per-line lyric comparison now derives every line score from one global,
monotonic word alignment. This lets the matcher skip genuinely omitted blocks,
resynchronize at later sections, and assign repeated hooks to their corresponding
occurrences. It replaces the previous greedy line search that could jump to a
later repeated hook and mark the remainder of the song as absent.

The global sequence-recall definition, thresholds, machine route, human gate,
transcription process, and generation behavior are unchanged. Alignment is
bounded to 6,000,000 dynamic-programming cells and terminates safely above that
limit.

Existing candidate evidence retains its archived transcript and analysis file.
The read path projects the current version-2 alignment from those stored words,
so dashboard refresh, revision drafting, and export metadata receive the repair
without rerunning Whisper or silently rewriting the evidence file.

## Files changed

```text
- lib/soul_core/music_candidate_analysis_service.rb
- scripts/verify-music-studio-a3-vocal-analysis.rb
- docs/soul/MUSIC_STUDIO_A3_LYRIC_ALIGNMENT_REVIEW.md
```

## Commands and deterministic results

```text
ruby scripts/verify-music-studio-a3-vocal-analysis.rb  PASS
ruby -c lib/soul_core/music_candidate_analysis_service.rb PASS
git diff --check PASS
```

No local LLM eval applies. The repair is deterministic and its regression fixture
covers omitted verses followed by repeated hooks, a bridge, final hook, and outro.

## Memory, lifecycle, and risk

- Memory keys: none.
- Lifecycle states touched: `blocked_for_human_review` only; existing failure and
  cancellation paths are unchanged.
- Risk class: local read/derived-evidence calculation; no authority mutation.

## Known weaknesses

- Exact word alignment treats substitutions as misses; it does not attempt
  phonetic equivalence such as `wait`/`weep`.
- Existing stored analyses are projected through the repaired aligner on read;
  their archived version-1 line breakdown remains unchanged on disk.

## Human review checklist

```text
[ ] Repeated hooks are assigned to all corresponding occurrences
[ ] Genuine omitted blocks remain visible
[ ] Later bridge/final hook/outro resynchronize correctly
[ ] Machine route remains advisory and human-gated
[ ] Six-million-cell bound is acceptable
[ ] Approve candidate for commit/merge
```
