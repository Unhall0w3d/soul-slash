# AMD-only foreground voice transcription

Human direction, 2026-09-05: use large-v3-turbo on RX 6900 XT for voice
transcription. With AMD chat, temporarily release idle chat and restore it;
with NVIDIA Qwen, leave Qwen unchanged. No CPU fallback. Free Core must reject
transcription without loading any model. Implement across dashboard and Voice
Presence, not only the qualification harness.

The user's subsequent clarification authorizes borrowing idle AMD-linked chat
models regardless of name, including GPT-OSS. Snapshot all resident models of
the managed AMD Ollama chat/Dev services and restore their exact identities and
contexts. Non-model creative workloads and foreign processes still block;
they are not authorized eviction targets.
Hold the existing runtime control lock across admission, work, and recovery;
never interrupt active leases. Verify hardware identity and GPU execution.
Keep canonical conversation history unchanged; return a transcript only after
recovery. Never mutate saved Core/profile selections. A hard interruption leaves
a minimal private pending receipt for explicit recovery review, not a daemon.

Reuse bounded normalization, silence rejection, child cancellation, and cleanup.
No recordings, downloads, package changes, new units, or new listeners. Reuse
the locally benchmarked Vulkan artifact in a durable qualification directory.
Free remains selected during implementation; live loaded-Core acceptance is a
separate test requiring deliberate Core selection.

Required deterministic checks: Free and corrupt/unknown selection refusal;
Core recheck under lock; idle AMD release/recovery; NVIDIA unchanged; busy work,
Dev, unknown hardware and insufficient VRAM refusal; partial stop, recognition,
cancellation, cleanup, and restoration failure; pending receipt durability;
AMD proof with no CPU fallback; all production call sites use shared routing.
Run voice transcription, Voice Presence, runtime handoff/control regressions.
Document evidence and remaining live acceptance in a human review artifact.
