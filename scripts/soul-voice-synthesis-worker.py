#!/usr/bin/env python3
"""Private app-owned Supertonic worker; no socket, listener, or durable state."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

from supertonic import TTS

MAX_TEXT_CHARACTERS = 2_000
MAX_OUTPUT_BYTES = 20 * 1024 * 1024
VOICES = ("F3", "M3")


def emit(**value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def contained_file(path_value, session):
    path = Path(path_value).resolve(strict=False)
    if path.parent != session or path.name not in {"response.wav"}:
        raise ValueError("speech output is outside the private session")
    if path.exists() or path.is_symlink():
        raise ValueError("speech output already exists")
    return path


def validate_assets(model_dir, manifest):
    for relative, expected in manifest["assets"].items():
        path = model_dir / relative
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"pinned synthesis asset is missing: {relative}")
        hasher = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                hasher.update(chunk)
        digest = hasher.hexdigest()
        if digest != expected:
            raise ValueError(f"synthesis asset digest does not match: {relative}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--session", required=True)
    args = parser.parse_args()

    session = Path(args.session).resolve(strict=True)
    model_dir = Path(args.model_dir).resolve(strict=True)
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    if manifest.get("schema_version") != "soul.voice_synthesis.models.v1":
        raise ValueError("unsupported synthesis manifest")
    validate_assets(model_dir, manifest)

    loaded_at = time.monotonic()
    tts = TTS(model="supertonic-3", model_dir=str(model_dir), auto_download=False)
    styles = {voice: tts.get_voice_style(voice) for voice in VOICES}
    emit(type="ready", load_ms=round((time.monotonic() - loaded_at) * 1000))

    for line in sys.stdin:
        output = None
        try:
            request = json.loads(line)
            request_id = str(request["request_id"])
            text = str(request["text"]).strip()
            voice = str(request["voice"])
            speed = float(request["speed"])
            steps = int(request["steps"])
            language = str(request["language"])
            output = contained_file(request["output"], session)
            if not text or len(text) > MAX_TEXT_CHARACTERS or len(text.encode("utf-8")) > 8 * 1024:
                raise ValueError("speech text is outside the bounded length")
            if voice not in styles:
                raise ValueError("speech voice is unavailable")
            if not 0.7 <= speed <= 2.0 or not 1 <= steps <= 20:
                raise ValueError("speech controls are outside reviewed bounds")

            started = time.monotonic()
            waveform, _duration = tts.synthesize(
                text, voice_style=styles[voice], total_steps=steps,
                speed=speed, lang=language,
            )
            tts.save_audio(waveform, output)
            os.chmod(output, 0o600)
            if not output.is_file() or output.is_symlink() or not 44 <= output.stat().st_size <= MAX_OUTPUT_BYTES:
                raise ValueError("speech output is invalid")
            emit(
                type="result", request_id=request_id, audio_path=str(output),
                synthesis_ms=round((time.monotonic() - started) * 1000),
            )
        except Exception as error:
            if output is not None and output.parent == session:
                output.unlink(missing_ok=True)
            emit(type="failure", request_id=str(locals().get("request_id", "unknown")), error=str(error)[:300])


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        emit(type="fatal", error=str(error)[:300])
        raise
