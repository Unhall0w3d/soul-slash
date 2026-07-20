# Chat Intent and Interaction Hardening Brief

Status: Operator-approved implementation slice

## Purpose

Give every conversational route one deterministic prerequisite: mentioning a
capability is not the same as asking Soul to use it. The boundary must preserve
natural conversation while keeping explicit foreground requests available.

## Approved scope

- Classify a message as ordinary conversation, an action request, an
  information request, or a terse explicit request before capability routing.
- Reuse that request shape in the legacy intent router, deterministic tool
  catalog, declared capability registry, research routing, artifact creation,
  and initial creative-workflow detection.
- Preserve natural lead-ins such as `Well, take a look...` and `Soul, check...`.
- Distinguish questions about an unavailable capability from requests to use
  it. A support question explains the boundary; an explicit task may enter the
  existing human-reviewed capability-gap lane.
- Add deterministic regression coverage for status, skill inventory, Core
  control, research, artifacts, creative work, and capability gaps.
- Validate conversational behavior against the configured local chat model,
  without treating model output as routing or safety authority.

## Boundaries

This slice does not:

- add a skill, mutation, approval bypass, provider, service, watcher, queue, or
  unattended process;
- infer authority from model output;
- change exact Core, generation, deletion, export, or publication gates;
- make every natural-language command valid; ambiguous messages remain
  conversation and Soul may ask a clarifying question;
- promise equivalent persona fidelity from Gemma and Qwen without human live
  review on both Cores.

## Acceptance matrix

| Message | Required route |
|---|---|
| `I'm working on your skills.` | conversation |
| `What skills do you have?` | skill catalog only |
| `I'm reviewing system status.` | conversation |
| `Check system status.` | bounded host status |
| `How is Soul doing today?` | conversation |
| `Music Core sounds useful later.` | conversation |
| `Switch to Music Core.` | exact Core preview |
| `I'd like to make a song someday.` | conversation |
| `Create a 90-second instrumental song.` | creative workflow |
| `That research was useful.` | conversation |
| `Research current Ruby security guidance.` | bounded web research |
| `I created a report yesterday.` | conversation |
| `Create an architecture report.` | artifact preview |
| `Do you support SMART health?` | capability information |
| `Check SMART health.` | declared capability-gap lane |

## Completion condition

The candidate must pass the focused matrix and relevant historical routing,
artifact, capability, research, creative, and persona regressions. The Operator
must then review live Gemma conversation behavior and, when convenient, repeat
the conversational cases under the Qwen reserve before this slice is treated as
fully accepted.
