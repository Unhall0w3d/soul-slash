#!/usr/bin/env python3
"""One-shot Supertonic synthesis runner.

This process owns one request, reads text from a private file, writes one WAV,
and exits. It deliberately does not expose an HTTP server or resident engine.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from supertonic import TTS


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--voice", required=True)
    parser.add_argument("--language", default="en")
    parser.add_argument("--steps", type=int, default=10)
    parser.add_argument("--speed", type=float, default=1.0)
    arguments = parser.parse_args()

    text_path = Path(arguments.input)
    output_path = Path(arguments.output)
    text = text_path.read_text(encoding="utf-8")
    if not text.strip():
        raise ValueError("speech text is empty")

    tts = TTS(model="supertonic-3", model_dir=arguments.model_dir, auto_download=False)
    voice = tts.get_voice_style(arguments.voice)
    waveform, _duration = tts.synthesize(
        text,
        voice_style=voice,
        total_steps=arguments.steps,
        speed=arguments.speed,
        lang=arguments.language,
    )
    tts.save_audio(waveform, output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
