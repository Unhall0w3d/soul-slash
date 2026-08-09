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
    QCheckBox, QComboBox, QPushButton, QVBoxLayout, QWidget
)
from soul_voice_notification_observer import NotificationMonitorParser


class PresenceWindow(QMainWindow):
    def __init__(self, args):
        super().__init__()
        self.args = args
        self.session = Path(tempfile.mkdtemp(prefix="soul-voice-presence-"))
        os.chmod(self.session, 0o700)
        self.worker_buffer = ""
        self.bridge_buffer = ""
        self.notification_buffer = ""
        self.failure_count = 0
        self.current_state = "starting"
        self.restart_requested = False
        self.settings = QSettings("SoulSlash", "VoicePresence")
        self.worker = None
        self.bridge = None
        self.player = None
        self.cue_player = None
        self.notification_player = None
        self.notification_observer = None
        self.notification_parser = NotificationMonitorParser()
        self.notification_last_spoken = {}
        self.setWindowTitle("Soul / Voice Presence")
        self.setWindowIcon(QIcon(args.icon))
        self.setMinimumSize(QSize(440, 620))
        self.resize(480, 680)
        self._build()
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
        notification_row = QHBoxLayout()
        self.notification_toggle = QCheckBox("Observe desktop notifications", objectName="notificationToggle")
        self.notification_toggle.setChecked(self.settings.value("observe_desktop_notifications", False, type=bool))
        self.notification_toggle.toggled.connect(self.toggle_notification_observer)
        self.notification_status = QLabel("Notification observer off", objectName="notificationStatus")
        self.notification_status.setAlignment(Qt.AlignCenter)
        self.notification_status.setWordWrap(True)
        notification_row.addStretch(1)
        notification_row.addWidget(self.notification_toggle)
        notification_row.addStretch(1)
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
        layout.addLayout(notification_row)
        layout.addWidget(self.notification_status)
        layout.addLayout(buttons)
        self.setCentralWidget(root)
        self.setStyleSheet("""
          #root { background: #060b11; color: #c9f7ff; border: 1px solid #a9802c; }
          #eyebrow { color: #22d3ee; font: 600 12px monospace; letter-spacing: 2px; }
          #title { color: #e9c766; font: 34px "Cormorant Garamond", serif; }
          #status { color: #d7f8fb; font: 600 17px "Inter", sans-serif; }
          #detail { color: #86a9b2; font: 13px "Inter", sans-serif; }
          #voiceLabel { color: #749da7; font: 11px monospace; letter-spacing: 1px; }
          #notificationToggle { color: #b9f4fa; font: 12px "Inter", sans-serif; }
          #notificationStatus { color: #749da7; font: 11px "Inter", sans-serif; }
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
            "listening": 'Say “Hey Soul,” then speak one request.',
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
        process = self.worker if which == "worker" else self.bridge
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
            self.detail.setText(f'Say “Hey Soul,” then speak one request. · Microphone: {signal}')
        elif event_type == "utterance":
            self.run_bridge(event["path"])
        elif event_type in {"turn_failure", "fatal"}:
            self.turn_failed(event.get("summary", "The voice turn failed safely."))
        elif event_type == "followup_expired":
            self.set_state("listening", event.get("summary", 'Listening locally for “Hey Soul”.'))
        elif event_type == "result":
            if event.get("audio_path"):
                self.failure_count = 0
                self.play(event["audio_path"])
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
        if self.notification_toggle.isChecked():
            self.start_notification_observer()

    def toggle_notification_observer(self, enabled):
        self.settings.setValue("observe_desktop_notifications", enabled)
        self.settings.sync()
        if enabled:
            self.start_notification_observer()
        else:
            self.stop_notification_observer()

    def start_notification_observer(self):
        if self.notification_observer and self.notification_observer.state() == QProcess.Running:
            return
        self.notification_parser = NotificationMonitorParser()
        self.notification_observer = QProcess(self)
        self.notification_observer.setProcessChannelMode(QProcess.SeparateChannels)
        self.notification_observer.readyReadStandardOutput.connect(self.process_notification_lines)
        self.notification_observer.finished.connect(self.notification_observer_stopped)
        self.notification_observer.start("dbus-monitor", [
            "--session",
            "type='method_call',interface='org.freedesktop.Notifications',member='Notify'",
        ])
        if not self.notification_observer.waitForStarted(1200):
            self.notification_status.setText("Notification observer unavailable; Noctalia remains unchanged.")
            self.notification_toggle.blockSignals(True)
            self.notification_toggle.setChecked(False)
            self.notification_toggle.blockSignals(False)
            self.settings.setValue("observe_desktop_notifications", False)
            self.settings.sync()
            return
        self.notification_status.setText("Observing standard desktop notifications; contents are never retained.")

    def stop_notification_observer(self):
        process = self.notification_observer
        self.notification_observer = None
        self.notification_buffer = ""
        self.notification_parser = NotificationMonitorParser()
        if process and process.state() != QProcess.NotRunning:
            process.terminate()
            if not process.waitForFinished(1200):
                process.kill()
                process.waitForFinished(600)
        self.notification_status.setText("Notification observer off")

    def notification_observer_stopped(self, _code, _status):
        if self.notification_observer and self.notification_toggle.isChecked():
            self.notification_status.setText("Notification observer stopped safely; re-enable it to try again.")

    def process_notification_lines(self):
        if not self.notification_observer:
            return
        data = bytes(self.notification_observer.readAllStandardOutput()).decode("utf-8", "replace")
        lines = (self.notification_buffer + data).split("\n")
        self.notification_buffer = lines.pop()
        for line in lines:
            for observation in self.notification_parser.feed(line):
                self.handle_notification_observation(observation)

    def handle_notification_observation(self, observation):
        label = observation.source.replace("_", " ").title()
        if observation.delivery == "suppressed":
            self.notification_status.setText(f"{label} classified as social; voice suppressed.")
            return
        if observation.delivery != "spoken":
            self.notification_status.setText(f"{label} classified as {observation.category.replace('_', ' ')}; visual only.")
            return
        if self.current_state != "listening":
            self.notification_status.setText(f"{label} needs attention; voice deferred while Soul is active.")
            return
        now = time.monotonic()
        prior = self.notification_last_spoken.get(observation.source, now - 90.0)
        if now - prior < 90.0:
            self.notification_status.setText(f"{label} urgent notice deduplicated locally.")
            return
        self.notification_last_spoken[observation.source] = now
        self.notification_status.setText(f"{label} urgent communication notice played.")
        self.play_notification(observation.spoken_key)

    def run_bridge(self, capture):
        self.set_state("hearing", "Resolving your voice.")
        output = self.session / "response.wav"
        output.unlink(missing_ok=True)
        self.bridge = QProcess(self)
        self.bridge.setWorkingDirectory(self.args.project_root)
        self.bridge.setProcessChannelMode(QProcess.MergedChannels)
        self.bridge.readyReadStandardOutput.connect(lambda: self.process_lines("bridge"))
        self.bridge.finished.connect(self.bridge_stopped)
        self.bridge.start(self.args.bridge, [capture, str(output), self.selected_voice()])

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

    def play_notification(self, key):
        if not key:
            return
        voice = self.selected_voice().lower()
        path = Path(self.args.project_root) / "assets" / "notifications" / f"{voice}-{key}.wav"
        if not path.is_file():
            return
        self.notification_player = QProcess(self)
        self.notification_player.start("pw-play", [str(path)])

    def play(self, path):
        self.set_state("speaking", "Soul is speaking.")
        self.player = QProcess(self)
        self.player.finished.connect(self.turn_complete)
        self.player.start("pw-play", [path])

    def turn_complete(self):
        for path in self.session.glob("*.wav"):
            path.unlink(missing_ok=True)
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
            self.set_state("listening", 'Listening locally for “Hey Soul”.')

    def open_followup(self):
        if self.worker and self.worker.state() == QProcess.Running:
            self.worker.write(b"followup\n")
            self.set_state("followup", "Follow-up open for five seconds.")

    def toggle_pause(self):
        if not self.worker or self.worker.state() != QProcess.Running:
            self.start_worker()
            self.pause.setText("Pause listening")
            return
        if self.current_state in {"paused", "failed"}:
            self.failure_count = 0
            self.resume_worker()
            self.pause.setText("Pause listening")
        else:
            self.worker.write(b"pause\n")
            self.pause.setText("Resume listening")

    def stop_children(self):
        self.stop_notification_observer()
        for process in (self.cue_player, self.notification_player, self.player, self.bridge, self.worker):
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
