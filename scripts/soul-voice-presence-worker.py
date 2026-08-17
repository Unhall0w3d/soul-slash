#!/usr/bin/env python3
"""Bounded local wake/capture worker. It owns no state after process exit."""

import argparse
import json
import math
import os
import select
import signal
import struct
import subprocess
import sys
import time
import wave
from pathlib import Path

STOP = False


def emit(**value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def stop(_signal=None, _frame=None):
    global STOP
    STOP = True


def rms(pcm):
    if not pcm:
        return 0
    samples = struct.unpack("<%dh" % (len(pcm) // 2), pcm)
    return math.sqrt(sum(value * value for value in samples) / len(samples))


def write_wav(path, frames, sample_rate):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(b"".join(frames))
    os.chmod(path, 0o600)


def start_recorder(command):
    return subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)


def stop_recorder(recorder):
    if recorder.poll() is not None:
        return
    recorder.terminate()
    try:
        recorder.wait(timeout=2)
    except subprocess.TimeoutExpired:
        recorder.kill()
        recorder.wait(timeout=1)


def capture_command(
    stream, output, capture, speech_start_timeout=None,
    no_speech_summary="No speech followed the wake phrase.", metrics=None,
):
    rate = capture["sample_rate"]
    block_bytes = int(rate * 0.08) * 2
    threshold = int(capture["speech_rms_threshold"])
    timeout = speech_start_timeout if speech_start_timeout is not None else capture["speech_start_timeout_seconds"]
    started_at = time.monotonic()
    speech_at = None
    silence_at = None
    frames = []
    while not STOP:
        if speech_at is None and time.monotonic() - started_at > timeout:
            return False, no_speech_summary
        if speech_at is not None and time.monotonic() - speech_at > capture["maximum_utterance_seconds"]:
            break
        chunk = stream.read(block_bytes)
        if not chunk:
            return False, "The microphone path closed."
        level = rms(chunk)
        if speech_at is None:
            if level >= threshold:
                speech_at = time.monotonic()
                if metrics is not None:
                    metrics["speech_start_ms"] = round((speech_at - started_at) * 1000)
                frames.append(chunk)
        else:
            frames.append(chunk)
            if level < threshold:
                silence_at = silence_at or time.monotonic()
                if time.monotonic() - silence_at >= capture["trailing_silence_seconds"]:
                    break
            else:
                silence_at = None
    duration = sum(len(frame) for frame in frames) / 2 / rate
    if duration < capture["minimum_utterance_seconds"]:
        return False, "The utterance was too short."
    write_wav(output, frames, rate)
    if metrics is not None:
        metrics["capture_elapsed_ms"] = round((time.monotonic() - started_at) * 1000)
        metrics["captured_audio_ms"] = round(duration * 1000)
    return True, f"Captured {duration:.1f} seconds."


def main():
    import sherpa_onnx

    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--session", required=True)
    args = parser.parse_args()
    manifest = json.loads(Path(args.manifest).read_text())
    capture = manifest["capture"]
    runtime = Path(args.runtime)
    session = Path(args.session)
    command = [
        "pw-record", "-a", "--target", args.source, "--rate", str(capture["sample_rate"]),
        "--channels", "1", "--format", "s16", "-"
    ]
    recorder = start_recorder(command)
    spotter = sherpa_onnx.KeywordSpotter(
        tokens=str(runtime / "model" / "tokens.txt"),
        encoder=str(runtime / "model" / "encoder.onnx"),
        decoder=str(runtime / "model" / "decoder.onnx"),
        joiner=str(runtime / "model" / "joiner.onnx"),
        keywords_file=str(runtime / "model" / "keywords.txt"),
        num_threads=1,
        provider="cpu",
        max_active_paths=4,
    )
    stream = spotter.create_stream()
    rate = capture["sample_rate"]
    chunk_bytes = int(rate * capture["wake_chunk_milliseconds"] / 1000) * 2
    last_level_emit = 0.0
    emit(type="state", state="listening", summary='Listening locally for “Hey Soul”.')
    try:
        while not STOP:
            ready, _, _ = select.select([sys.stdin, recorder.stdout], [], [], 0.2)
            if sys.stdin in ready:
                control = sys.stdin.readline().strip()
                if control == "stop":
                    break
                if control == "pause":
                    stop_recorder(recorder)
                    emit(type="state", state="paused", summary="Listening paused by the Operator.")
                    while not STOP:
                        line = sys.stdin.readline().strip()
                        if line in ("resume", "stop"):
                            if line == "stop":
                                return
                            recorder = start_recorder(command)
                            emit(type="state", state="listening", summary='Listening locally for “Hey Soul”.')
                            break
            if recorder.stdout not in ready:
                continue
            pcm = recorder.stdout.read(chunk_bytes)
            if not pcm:
                raise RuntimeError("configured microphone stream closed")
            samples = [value / 32768.0 for value in struct.unpack("<%dh" % (len(pcm) // 2), pcm)]
            now = time.monotonic()
            if now - last_level_emit >= 0.4:
                emit(type="level", rms=round(rms(pcm), 1))
                last_level_emit = now
            stream.accept_waveform(rate, samples)
            while spotter.is_ready(stream):
                spotter.decode_stream(stream)
            result = spotter.get_result(stream)
            if not result:
                continue
            turn_started = time.monotonic()
            emit(type="state", state="awakened", summary="Wake phrase recognized.")
            time.sleep(float(capture.get("post_wake_capture_delay_seconds", 0.18)))
            output = session / f"utterance-{int(time.time() * 1000)}.wav"
            timing = {}
            ok, summary = capture_command(recorder.stdout, output, capture, metrics=timing)
            if ok:
                while ok and not STOP:
                    emit(
                        type="utterance", path=str(output), summary=summary,
                        turn_started_monotonic=turn_started, timing=timing,
                    )
                    stop_recorder(recorder)
                    control = sys.stdin.readline().strip()
                    if control == "stop":
                        return
                    recorder = start_recorder(command)
                    if control != "followup":
                        break
                    followup_summary = "No follow-up heard. Wake-word listening resumed."
                    emit(
                        type="state", state="followup",
                        summary="Follow-up open for five seconds."
                    )
                    output = session / f"utterance-{int(time.time() * 1000)}.wav"
                    turn_started = time.monotonic()
                    timing = {}
                    ok, summary = capture_command(
                        recorder.stdout, output, capture,
                        speech_start_timeout=capture["followup_speech_start_timeout_seconds"],
                        no_speech_summary=followup_summary,
                        metrics=timing,
                    )
                    if not ok:
                        if summary == followup_summary:
                            emit(type="followup_expired", summary=summary)
                        else:
                            emit(type="turn_failure", summary=summary)
                        break
            else:
                emit(type="turn_failure", summary=summary)
            stream = spotter.create_stream()
            emit(type="state", state="listening", summary='Listening locally for “Hey Soul”.')
    finally:
        stop_recorder(recorder)


if __name__ == "__main__":
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, stop)
    try:
        main()
    except Exception as error:
        emit(type="fatal", state="failed", summary=str(error)[:300])
        raise
