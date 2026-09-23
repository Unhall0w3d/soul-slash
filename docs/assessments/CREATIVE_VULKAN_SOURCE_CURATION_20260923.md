# Creative Vulkan source curation — 2026-09-23

Status: isolated candidate for human merge review, stacked on the routed
voice/Core candidate. The bounded Soul-Lite music adaptation was previously
authorized, but new creative outputs still need Operator listening or visual
review. This curation did not render, download or select a model, change GPU
ownership, or publish an artifact.

Music, still-image, motion and native-video profiles now state an exact Vulkan
device selector and visible-device index. Their foreground launchers validate
and pass that selection to the renderer. The separate native-video profiles
retain their own resource and duration bounds. Soul-Lite music use remains
bound to the exact generation confirmation and the reviewed AMD lease.

Seven targeted verifiers passed under Ruby 4.0.7 with Prism: music feasibility,
Visual Studio A1/A2, motion qualification, generated motion, native video, and
conversational creative routing. `git diff --check` passed. These fixtures
establish source behavior, not the quality, timing or resource safety of a
new live render on another host.

Before merge or installation, review the pinned model/runtime artifacts and
GPU selector against the target host, run a bounded live generation in each
lane being promoted, and inspect outputs. Keep those operator acceptance
results separate from these deterministic checks.
