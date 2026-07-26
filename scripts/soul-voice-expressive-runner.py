#!/usr/bin/env python3
"""One-shot offline Chatterbox synthesis runner for Soul."""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
import torchaudio as ta
from chatterbox.tts import ChatterboxTTS


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--device", choices=("cpu", "cuda"), required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--exaggeration", type=float, default=0.7)
    parser.add_argument("--cfg-weight", type=float, default=0.3)
    arguments = parser.parse_args()

    text = Path(arguments.input).read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError("speech text is empty")
    if not Path(arguments.reference).is_file():
        raise ValueError("conditioning audio is missing")
    if arguments.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA is unavailable")

    torch.manual_seed(arguments.seed)
    model = ChatterboxTTS.from_local(Path(arguments.model_dir), arguments.device)
    waveform = model.generate(
        text,
        audio_prompt_path=arguments.reference,
        exaggeration=arguments.exaggeration,
        cfg_weight=arguments.cfg_weight,
    )
    ta.save(arguments.output, waveform, model.sr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
