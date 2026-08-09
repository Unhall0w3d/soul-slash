#!/usr/bin/env python3
"""Ephemeral, metadata-only parser for Voice Presence desktop notifications.

The visible Voice Presence application owns the dbus-monitor child.  This
module deliberately retains neither the notification summary nor its body:
only a reviewed application class, delivery posture, and static phrase key are
returned to the application.
"""

from __future__ import annotations

from dataclasses import dataclass
import re


@dataclass(frozen=True)
class NotificationObservation:
    source: str
    category: str
    delivery: str
    spoken_key: str | None = None


def _normalise(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def classify_notification(app_name: str, desktop_entry: str = "", urgency: int = 1) -> NotificationObservation:
    """Classify only application metadata; unknown sources stay visual-only."""
    identity = _normalise(desktop_entry or app_name)
    if identity in {"discord", "discordcanary", "discordptb"}:
        source, category = "discord", "communication_message"
    elif identity in {"webex", "ciscowebex", "webexmeetings"}:
        source, category = "webex", "communication_message"
    elif identity in {"teams", "msteams", "microsoftteams"}:
        source, category = "teams", "communication_message"
    elif identity == "steam":
        return NotificationObservation("steam", "gaming_activity", "visual_only")
    elif identity in {"facebook", "facebookcom", "messenger"}:
        return NotificationObservation("social", "social_activity", "suppressed")
    else:
        return NotificationObservation("unknown", "unclassified", "visual_only")

    if urgency >= 2:
        return NotificationObservation(source, "communication_urgent", "spoken", "communication-urgent")
    return NotificationObservation(source, category, "visual_only")


class NotificationMonitorParser:
    """Consume dbus-monitor lines and discard raw notification text immediately."""

    _STRING = re.compile(r'^\s*(?:variant\s+)?string\s+"(.*)"\s*$')
    _NUMBER = re.compile(r"\b(?:byte|uint32|int32)\s+(\d+)\b")

    def __init__(self) -> None:
        self._active = False
        self._first_string = True
        self._app_name = ""
        self._desktop_entry = ""
        self._urgency = 1
        self._pending_hint: str | None = None
        self._positional_strings = 0
        self._array_sections = 0

    def feed(self, line: str) -> list[NotificationObservation]:
        observations: list[NotificationObservation] = []
        if line.startswith("method call"):
            observation = self._finish()
            if observation:
                observations.append(observation)
            self._active = "interface=org.freedesktop.Notifications" in line and "member=Notify" in line
            self._first_string = True
            self._app_name = ""
            self._desktop_entry = ""
            self._urgency = 1
            self._pending_hint = None
            self._positional_strings = 0
            self._array_sections = 0
            return observations
        if not self._active:
            return observations

        if line.lstrip().startswith("array ["):
            self._array_sections += 1
            return observations

        string_match = self._STRING.match(line)
        if string_match:
            value = string_match.group(1)
            if self._positional_strings == 0:
                self._app_name = value
                self._first_string = False
                self._positional_strings += 1
                return observations
            if self._positional_strings < 4:
                # app_icon, summary, and body are deliberately discarded without
                # interpretation. They must not influence classification.
                self._positional_strings += 1
                return observations
            if self._array_sections < 2:
                return observations
            if value in {"urgency", "desktop-entry", "category"}:
                self._pending_hint = value
            elif self._pending_hint == "desktop-entry":
                self._desktop_entry = value
                self._pending_hint = None
            elif self._pending_hint == "category":
                self._pending_hint = None
            return observations

        if self._pending_hint == "urgency":
            number_match = self._NUMBER.search(line)
            if number_match:
                self._urgency = int(number_match.group(1))
                self._pending_hint = None

        # Notify's final positional argument is expire_timeout.  The preceding
        # summary/body have already been ignored, so classification can happen.
        if line.lstrip().startswith("int32 "):
            observation = self._finish()
            if observation:
                observations.append(observation)
        return observations

    def close(self) -> list[NotificationObservation]:
        observation = self._finish()
        return [observation] if observation else []

    def _finish(self) -> NotificationObservation | None:
        if not self._active:
            return None
        self._active = False
        observation = classify_notification(self._app_name, self._desktop_entry, self._urgency)
        self._app_name = ""
        self._desktop_entry = ""
        self._pending_hint = None
        self._positional_strings = 0
        self._array_sections = 0
        return observation
