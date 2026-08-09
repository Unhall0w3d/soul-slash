#!/usr/bin/env python3
"""Deterministic checks for the Voice Presence metadata-only notification observer."""

import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("observer", ROOT / "scripts" / "soul_voice_notification_observer.py")
observer = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = observer
SPEC.loader.exec_module(observer)


def notification(app, summary, body, urgency=1, desktop=None):
    hints = []
    if desktop:
        hints.extend([f'      string "desktop-entry"', f'         variant             string "{desktop}"'])
    hints.extend([f'      string "urgency"', f'         variant             byte {urgency}'])
    return [
        "method call time=1.0 sender=:1.1 -> destination=:1.2 serial=1 path=/org/freedesktop/Notifications; interface=org.freedesktop.Notifications; member=Notify",
        f'   string "{app}"', "   uint32 0", '   string ""',
        f'   string "{summary}"', f'   string "{body}"',
        "   array [", "   ]", "   array [", *hints, "   ]", "   int32 -1",
    ]


def parsed(lines):
    parser = observer.NotificationMonitorParser()
    results = []
    for line in lines:
        results.extend(parser.feed(line))
    results.extend(parser.close())
    return results


discord = parsed(notification("Discord", "private title", "private body", desktop="discord"))
assert discord == [observer.NotificationObservation("discord", "communication_message", "visual_only")]
urgent = parsed(notification("Cisco Webex", "private title", "private body", urgency=2, desktop="webex"))
assert urgent == [observer.NotificationObservation("webex", "communication_urgent", "spoken", "communication-urgent")]
steam = parsed(notification("Steam", "private title", "private body"))
assert steam == [observer.NotificationObservation("steam", "gaming_activity", "visual_only")]
social = parsed(notification("Facebook", "private title", "private body"))
assert social == [observer.NotificationObservation("social", "social_activity", "suppressed")]
unknown = parsed(notification("Browser", "Facebook message", "never retain this text"))
assert unknown == [observer.NotificationObservation("unknown", "unclassified", "visual_only")]
assert not any("private" in repr(item) or "retain" in repr(item) for item in discord + urgent + steam + social + unknown)

print("Voice Presence Notification Observer A3 verification complete: 6 deterministic checks.")
