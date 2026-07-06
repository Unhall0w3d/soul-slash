# Lessons Learned

## 2026-07-06: Qwen3 thinking mode can consume response budget

When Qwen3 is not given `/no_think`, it may spend the response budget in `reasoning_content` and produce no final `content`.

Use FAST mode with `/no_think` for routine/tool tasks.
Use THINK mode deliberately with a larger token budget for planning/reflection.

## 2026-07-06: GTX 1070 baseline runtime

Stable runtime:
- Qwen3 8B Q4_K_M
- llama.cpp server
- GTX 1070
- 4096 context
- f16 KV cache
- Flash Attention off
