"""Trusted read-only Blender A0 runtime probe.

This file is repository-owned. It does not save preferences or enable scripts
from a blend file.
"""

import json

import bpy
import gpu


def cycles_devices():
    addon = bpy.context.preferences.addons.get("cycles")
    if addon is None:
        return []
    preferences = addon.preferences
    try:
        preferences.get_devices()
    except Exception as error:  # Blender exposes backend-specific probe errors.
        return [{"type": "probe_error", "name": type(error).__name__}]
    return [
        {
            "name": str(device.name),
            "type": str(device.type),
            "id": str(device.id),
        }
        for device in preferences.devices
    ]


gpu.init()

payload = {
    "blender_version": bpy.app.version_string,
    "background": bool(bpy.app.background),
    "active_engine": bpy.context.scene.render.engine,
    "gpu_backend": gpu.platform.backend_type_get(),
    "gpu_vendor": gpu.platform.vendor_get(),
    "gpu_renderer": gpu.platform.renderer_get(),
    "gpu_version": gpu.platform.version_get(),
    "cycles_devices": cycles_devices(),
}
print("SOUL_BLENDER_PROBE=" + json.dumps(payload, sort_keys=True))
