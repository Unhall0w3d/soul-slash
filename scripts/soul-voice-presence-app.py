#!/usr/bin/env python3
"""Visible consent surface and lifecycle controller for Soul Voice Presence."""

import argparse
import json
import os
import shutil
import signal
import sys
import tempfile
import time
from pathlib import Path

from PySide6.QtCore import QEasingCurve, QProcess, QPropertyAnimation, QSettings, QSize, Qt, QTimer
from PySide6.QtGui import QColor, QCloseEvent, QIcon, QPixmap
from PySide6.QtWidgets import (
    QApplication, QGraphicsDropShadowEffect, QHBoxLayout, QLabel, QMainWindow,
    QComboBox, QPushButton, QVBoxLayout, QWidget
)


class PresenceWindow(QMainWindow):
    def __init__(self, args):
        super().__init__()
        self.args = args
        self.session = Path(tempfile.mkdtemp(prefix="soul-voice-presence-"))
        os.chmod(self.session, 0o700)
        self.worker_buffer = ""
        self.bridge_buffer = ""
        self.synthesis_buffer = ""
        self.failure_count = 0
        self.current_state = "starting"
        self.restart_requested = False
        self.settings = QSettings("SoulSlash", "VoicePresence")
        self.worker = None
        self.bridge = None
        self.player = None
        self.cue_player = None
        self.synthesis_worker = None
        self.synthesis_ready = False
        self.pending_speech = None
        self.active_turn_started = None
        self.last_latency_summary = ""
        self.setWindowTitle("Soul / Voice Presence")
        self.setWindowIcon(QIcon(args.icon))
        self.setMinimumSize(QSize(440, 620))
        self.resize(480, 680)
        self._build()
        QTimer.singleShot(0, self.start_synthesis_worker)
        QTimer.singleShot(0, self.start_worker)

    def _build(self):
        root = QWidget(objectName="root")
        layout = QVBoxLayout(root)
        layout.setContentsMargins(34, 28, 34, 28)
        layout.setSpacing(15)
        eyebrow = QLabel("LOCAL VOICE PRESENCE", objectName="eyebrow")
        eyebrow.setAlignment(Qt.AlignCenter)
        self.title = QLabel("Soul /", objectName="title")
        self.title.setAlignment(Qt.AlignCenter)
        self.portrait = QLabel(objectName="portrait")
        self.portrait.setAlignment(Qt.AlignCenter)
        self.portrait.setMinimumHeight(400)
        self.glow = QGraphicsDropShadowEffect()
        self.glow.setBlurRadius(28)
        self.glow.setColor(QColor("#22d3ee"))
        self.glow.setOffset(0, 0)
        self.portrait.setGraphicsEffect(self.glow)
        self.animation = QPropertyAnimation(self.glow, b"blurRadius", self)
        self.animation.setDuration(1500)
        self.animation.setStartValue(12)
        self.animation.setEndValue(42)
        self.animation.setEasingCurve(QEasingCurve.InOutSine)
        self.animation.setLoopCount(-1)
        self.status = QLabel("Starting local presence…", objectName="status")
        self.status.setAlignment(Qt.AlignCenter)
        self.status.setWordWrap(True)
        self.detail = QLabel("The microphone exists only while this window is open.", objectName="detail")
        self.detail.setAlignment(Qt.AlignCenter)
        self.detail.setWordWrap(True)
        voice_row = QHBoxLayout()
        voice_label = QLabel("RESPONSE VOICE", objectName="voiceLabel")
        self.voice_selector = QComboBox(objectName="voiceSelector")
        self.voice_selector.addItem("Feminine · F3", "F3")
        self.voice_selector.addItem("Masculine · M3", "M3")
        selected_voice = self.settings.value("response_voice", "F3")
        selected_index = self.voice_selector.findData(selected_voice if selected_voice in ("F3", "M3") else "F3")
        self.voice_selector.setCurrentIndex(max(0, selected_index))
        self.voice_selector.currentIndexChanged.connect(lambda _index: self.store_voice())
        voice_row.addStretch(1)
        voice_row.addWidget(voice_label)
        voice_row.addWidget(self.voice_selector)
        voice_row.addStretch(1)
        buttons = QHBoxLayout()
        self.pause = QPushButton("Pause listening", objectName="pause")
        self.pause.clicked.connect(self.toggle_pause)
        self.restart_button = QPushButton("Restart presence", objectName="restart")
        self.restart_button.clicked.connect(self.restart_application)
        self.close_button = QPushButton("Close presence", objectName="close")
        self.close_button.clicked.connect(self.close)
        buttons.addWidget(self.pause)
        buttons.addWidget(self.restart_button)
        buttons.addWidget(self.close_button)
        layout.addWidget(eyebrow)
        layout.addWidget(self.title)
        layout.addWidget(self.portrait, 1)
        layout.addWidget(self.status)
        layout.addWidget(self.detail)
        layout.addLayout(voice_row)
        layout.addLayout(buttons)
        self.setCentralWidget(root)
        self.setStyleSheet("""
          #root { background: #060b11; color: #c9f7ff; border: 1px solid #a9802c; }
          #eyebrow { color: #22d3ee; font: 600 12px monospace; letter-spacing: 2px; }
          #title { color: #e9c766; font: 34px "Cormorant Garamond", serif; }
          #status { color: #d7f8fb; font: 600 17px "Inter", sans-serif; }
          #detail { color: #86a9b2; font: 13px "Inter", sans-serif; }
          #voiceLabel { color: #749da7; font: 11px monospace; letter-spacing: 1px; }
          #voiceSelector { min-width: 155px; padding: 7px 28px 7px 10px; color: #b9f4fa;
                           background: #0b2530; border: 1px solid #287f8d; border-radius: 10px 2px 10px 2px;
                           font: 12px "Inter", sans-serif; }
          QPushButton { background: #0b2530; color: #8aefff; border: 1px solid #1598aa;
                        border-radius: 14px; padding: 10px 14px; font: 12px monospace; }
          QPushButton:hover { background: #103440; border-color: #32d5e8; }
          #close { color: #e8cb71; border-color: #8f7428; }
        """)
        self.set_state("starting", "Validating the local voice path.")

    def set_state(self, state, summary):
        self.current_state = state
        active = state in {"awakened", "hearing", "thinking", "speaking", "followup"}
        path = self.args.unmasked if active else self.args.masked
        pixmap = QPixmap(path)
        if not pixmap.isNull():
            pixmap = pixmap.scaled(360, 400, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            self.portrait.setPixmap(pixmap)
        self.status.setText(summary)
        self.detail.setText({
            "listening": 'Say “Hey Soul” or “Hey Slash,” then speak one request.',
            "paused": "The microphone path is paused. Resume when ready.",
            "thinking": "The ordinary Soul conversation and skill policies remain active.",
            "speaking": "Soul is responding through the selected local voice.",
            "followup": "Speak naturally within five seconds, or wait for wake-word listening to resume.",
            "failed": "No hidden retry is running.",
        }.get(state, "The microphone exists only while this window is open."))
        if state in {"listening", "awakened", "hearing", "thinking", "speaking", "followup"}:
            self.animation.start()
        else:
            self.animation.stop()
            self.glow.setBlurRadius(12)
        self.write_presence_state()

    def process_lines(self, which):
        process = {
            "worker": self.worker, "bridge": self.bridge,
            "synthesis": self.synthesis_worker,
        }[which]
        if process is None:
            return
        data = bytes(process.readAllStandardOutput()).decode("utf-8", "replace")
        attribute = f"{which}_buffer"
        buffer = getattr(self, attribute) + data
        lines = buffer.split("\n")
        setattr(self, attribute, lines.pop())
        for line in lines:
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            self.handle_event(which, event)

    def handle_event(self, origin, event):
        event_type = event.get("type")
        if event_type == "state":
            self.set_state(event.get("state", "failed"), event.get("summary", "Voice state changed."))
            if event.get("state") == "awakened":
                self.play_wake_cue()
        elif event_type == "progress":
            self.set_state("thinking", event.get("summary", "Soul is working."))
        elif event_type == "transcript":
            self.detail.setText(f'Heard: “{event.get("text", "")[:180]}”')
        elif event_type == "level" and self.current_state == "listening":
            level = float(event.get("rms", 0))
            signal = "voice activity" if level >= 120 else ("room signal" if level >= 12 else "quiet")
            self.detail.setText(f'Say “Hey Soul” or “Hey Slash,” then speak one request. · Microphone: {signal}')
        elif event_type == "utterance":
            self.run_bridge(event["path"], event)
        elif event_type == "timing":
            self.update_latency(event.get("timings", {}))
        elif event_type == "ready" and origin == "synthesis":
            self.synthesis_ready = True
        elif event_type == "speech_request":
            self.request_warm_speech(event)
        elif event_type == "failure" and origin == "synthesis":
            self.pending_speech = None
            self.turn_failed(event.get("error", "The local voice worker failed safely."))
        elif event_type == "fatal" and origin == "synthesis":
            self.synthesis_ready = False
            self.detail.setText("Warm voice preload is unavailable; the bounded one-shot path remains available.")
        elif event_type in {"turn_failure", "fatal"}:
            self.turn_failed(event.get("summary", "The voice turn failed safely."))
        elif event_type == "followup_expired":
            self.set_state("listening", event.get("summary", 'Listening locally for “Hey Soul” or “Hey Slash”.'))
        elif event_type == "result":
            if origin == "synthesis":
                pending = self.pending_speech or {}
                timings = dict(pending.get("timings") or {})
                timings["synthesis_ms"] = event.get("synthesis_ms", 0)
                if self.active_turn_started is not None:
                    timings["audio_ready_ms"] = round((time.monotonic() - self.active_turn_started) * 1000)
                self.pending_speech = None
                self.failure_count = 0
                self.update_latency(timings)
                self.play(event["audio_path"], replayed=False)
                return
            if event.get("audio_path"):
                self.failure_count = 0
                self.update_latency(event.get("timings", {}))
                self.play(event["audio_path"], replayed=bool(event.get("replayed")))
            else:
                self.turn_failed(event.get("error") or event.get("reply") or "The voice turn stopped safely.")

    def start_worker(self):
        self.worker = QProcess(self)
        self.worker.setProcessChannelMode(QProcess.MergedChannels)
        self.worker.readyReadStandardOutput.connect(lambda: self.process_lines("worker"))
        self.worker.finished.connect(self.worker_stopped)
        self.worker.start(self.args.worker_python, [
            self.args.worker, "--runtime", self.args.runtime, "--manifest", self.args.manifest,
            "--source", self.args.source, "--session", str(self.session)
        ])

    def start_synthesis_worker(self):
        if self.synthesis_worker and self.synthesis_worker.state() == QProcess.Running:
            return
        self.synthesis_ready = False
        self.synthesis_worker = QProcess(self)
        self.synthesis_worker.setProcessChannelMode(QProcess.MergedChannels)
        self.synthesis_worker.readyReadStandardOutput.connect(lambda: self.process_lines("synthesis"))
        self.synthesis_worker.finished.connect(self.synthesis_worker_stopped)
        self.synthesis_worker.start(self.args.synthesis_python, [
            self.args.synthesis_worker,
            "--model-dir", self.args.synthesis_model_dir,
            "--manifest", self.args.synthesis_manifest,
            "--session", str(self.session),
        ])

    def stop_synthesis_worker(self):
        process = self.synthesis_worker
        self.synthesis_worker = None
        self.synthesis_ready = False
        self.synthesis_buffer = ""
        self.pending_speech = None
        if process and process.state() != QProcess.NotRunning:
            process.terminate()
            if not process.waitForFinished(1800):
                process.kill()
                process.waitForFinished(1000)

    def synthesis_worker_stopped(self, code, _status):
        self.synthesis_ready = False
        if code != 0 and self.pending_speech and self.isVisible():
            self.pending_speech = None
            self.turn_failed("The warm local voice path stopped safely.")

    def request_warm_speech(self, event):
        if not self.synthesis_ready or not self.synthesis_worker or self.synthesis_worker.state() != QProcess.Running:
            self.turn_failed("The warm local voice path is unavailable; no hidden retry is running.")
            return
        self.pending_speech = event
        request = {
            "request_id": event["request_id"], "text": event["text"],
            "voice": event["voice"], "speed": event["speed"],
            "steps": event["steps"], "language": event["language"],
            "output": str(self.session / "response.wav"),
        }
        self.synthesis_worker.write((json.dumps(request, separators=(",", ":")) + "\n").encode("utf-8"))

    def run_bridge(self, capture, event):
        self.set_state("hearing", "Resolving your voice.")
        output = self.session / "response.wav"
        output.unlink(missing_ok=True)
        self.active_turn_started = float(event.get("turn_started_monotonic") or time.monotonic())
        timing = json.dumps(event.get("timing") or {}, separators=(",", ":"))
        self.bridge = QProcess(self)
        self.bridge.setWorkingDirectory(self.args.project_root)
        self.bridge.setProcessChannelMode(QProcess.MergedChannels)
        self.bridge.readyReadStandardOutput.connect(lambda: self.process_lines("bridge"))
        self.bridge.finished.connect(self.bridge_stopped)
        mode = "warm" if self.synthesis_ready else "one_shot"
        self.bridge.start(self.args.bridge, [
            capture, str(output), self.selected_voice(), str(self.session / "last-response.wav"),
            str(self.active_turn_started), timing, mode,
        ])

    def selected_voice(self):
        return str(self.voice_selector.currentData() or "F3")

    def store_voice(self):
        self.settings.setValue("response_voice", self.selected_voice())
        self.settings.sync()
        self.write_presence_state()
        self.detail.setText(f"{self.voice_selector.currentText()} will speak the next completed response.")

    def write_presence_state(self):
        state_root = Path(self.args.state_root)
        state_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = state_root / f".presence-{os.getpid()}.json"
        destination = state_root / "presence.json"
        temporary.write_text(json.dumps({
            "state": self.current_state,
            "notification_voice": self.selected_voice(),
        }), encoding="utf-8")
        os.chmod(temporary, 0o600)
        temporary.replace(destination)

    def play_wake_cue(self):
        if not Path(self.args.notification_wake).is_file():
            QApplication.beep()
            return
        self.cue_player = QProcess(self)
        self.cue_player.start("pw-play", [self.args.notification_wake])

    def play(self, path, replayed=False):
        source = Path(path)
        cached = self.session / "last-response.wav"
        if not replayed:
            cached.unlink(missing_ok=True)
            source.replace(cached)
            source = cached
        self.set_state("speaking", "Soul is speaking.")
        self.player = QProcess(self)
        self.player.started.connect(self.playback_started)
        self.player.finished.connect(self.turn_complete)
        self.player.start("pw-play", [str(source)])

    def playback_started(self):
        if self.active_turn_started is not None:
            elapsed = round((time.monotonic() - self.active_turn_started) * 1000)
            prefix = f"First audio {elapsed / 1000:.1f}s"
            self.last_latency_summary = f"{prefix} · {self.last_latency_summary}" if self.last_latency_summary else prefix

    def update_latency(self, timings):
        if not isinstance(timings, dict):
            return
        labels = (("transcription_ms", "STT"), ("route_ms", "Soul"), ("synthesis_ms", "TTS"))
        parts = [f"{label} {float(timings[key]) / 1000:.1f}s" for key, label in labels if key in timings]
        self.last_latency_summary = " · ".join(parts)

    def turn_complete(self):
        for path in self.session.glob("utterance-*.wav"):
            path.unlink(missing_ok=True)
        (self.session / "response.wav").unlink(missing_ok=True)
        self.open_followup()

    def bridge_stopped(self, code, _status):
        if code != 0 and self.current_state not in {"failed", "paused"}:
            self.turn_failed("The voice turn ended without a playable response.")

    def worker_stopped(self, code, _status):
        if code != 0 and self.isVisible():
            self.set_state("failed", "The local listening path stopped safely.")
            self.pause.setText("Resume listening")

    def turn_failed(self, summary):
        self.failure_count += 1
        if self.failure_count >= 3:
            self.set_state("failed", f"{summary} Listening paused after three failures.")
            self.pause.setText("Resume listening")
        else:
            self.set_state("failed", summary)
            QTimer.singleShot(1300, self.resume_worker)

    def resume_worker(self):
        if self.worker and self.worker.state() == QProcess.Running:
            self.worker.write(b"resume\n")
            self.set_state("listening", 'Listening locally for “Hey Soul” or “Hey Slash”.')

    def open_followup(self):
        if self.worker and self.worker.state() == QProcess.Running:
            self.worker.write(b"followup\n")
            self.set_state("followup", "Follow-up open for five seconds.")
            if self.last_latency_summary:
                self.detail.setText(f"Speak naturally within five seconds. · {self.last_latency_summary}")

    def toggle_pause(self):
        if not self.worker or self.worker.state() != QProcess.Running:
            self.start_worker()
            self.pause.setText("Pause listening")
            return
        if self.current_state in {"paused", "failed"}:
            self.failure_count = 0
            self.start_synthesis_worker()
            self.resume_worker()
            self.pause.setText("Pause listening")
        else:
            self.stop_synthesis_worker()
            self.worker.write(b"pause\n")
            self.pause.setText("Resume listening")

    def stop_children(self):
        self.stop_synthesis_worker()
        for process in (self.cue_player, self.player, self.bridge, self.worker):
            if process and process.state() != QProcess.NotRunning:
                process.terminate()
                if not process.waitForFinished(1800):
                    process.kill()
                    process.waitForFinished(1000)
        shutil.rmtree(self.session, ignore_errors=True)

    def restart_application(self):
        self.restart_requested = True
        self.set_state("starting", "Restarting Voice Presence with the current project files.")
        self.stop_children()
        QApplication.exit(75)

    def closeEvent(self, event: QCloseEvent):
        self.stop_children()
        (Path(self.args.state_root) / "presence.json").unlink(missing_ok=True)
        event.accept()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--worker-python", required=True)
    parser.add_argument("--worker", required=True)
    parser.add_argument("--bridge", required=True)
    parser.add_argument("--synthesis-python", required=True)
    parser.add_argument("--synthesis-worker", required=True)
    parser.add_argument("--synthesis-model-dir", required=True)
    parser.add_argument("--synthesis-manifest", required=True)
    parser.add_argument("--masked", required=True)
    parser.add_argument("--unmasked", required=True)
    parser.add_argument("--icon", required=True)
    parser.add_argument("--state-root", required=True)
    parser.add_argument("--notification-wake", required=True)
    args = parser.parse_args()
    application = QApplication(sys.argv)
    application.setApplicationName("Soul Voice Presence")
    window = PresenceWindow(args)
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, lambda _signum, _frame: window.close())
    signal_timer = QTimer()
    signal_timer.timeout.connect(lambda: None)
    signal_timer.start(250)
    window.show()
    return application.exec()


if __name__ == "__main__":
    raise SystemExit(main())
