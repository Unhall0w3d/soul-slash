#!/usr/bin/env python3
"""Repository-owned Blender Scene A1 adapter.

This adapter consumes a strict closed manifest and constructs scene data blocks only.
It intentionally avoids external imports, drivers, add-ons, scripts, and arbitrary
node authoring. It saves a validated ``.blend`` and optional still image.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--blend-path", required=True)
    parser.add_argument("--still-path", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--frame", type=int, default=1)
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    return parser.parse_args(arguments)


def require_type(value, label, expected):
    if not isinstance(value, expected):
        raise ValueError(f"{label} must be {expected.__name__}")


def require_string(value, label, min_length=1, max_length=80, pattern=None):
    require_type(value, label, str)
    if not (min_length <= len(value) <= max_length):
        raise ValueError(f"{label} length must be between {min_length} and {max_length}")
    if pattern and not re.fullmatch(pattern, value):
        raise ValueError(f"{label} has invalid pattern")


def require_int(value, label, minimum=None, maximum=None):
    if not isinstance(value, int):
        raise ValueError(f"{label} must be int")
    if minimum is not None and value < minimum:
        raise ValueError(f"{label} is below minimum {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{label} is above maximum {maximum}")


def require_number(value, label, minimum=None, maximum=None):
    if not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be numeric")
    if minimum is not None and value < minimum:
        raise ValueError(f"{label} is below minimum {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{label} is above maximum {maximum}")


def require_vector3(value, label, minimum=-1000.0, maximum=1000.0):
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(f"{label} must be a 3-item list")
    for coordinate in value:
        require_number(coordinate, f"{label} component", minimum, maximum)


def require_color(value, label):
    require_vector3(value, label, 0.0, 1.0)


def require_file_name(value, label):
    require_string(value, label, 1, 80, r"[a-zA-Z0-9._-]+")
    if "/" in value or "\\" in value:
        raise ValueError(f"{label} must be file name only")


def validate_manifest(manifest):
    def must_exist(obj, key):
        if key not in obj:
            raise ValueError(f"manifest missing key: {key}")

    def forbid_key(obj, key, context):
        if key in obj:
            raise ValueError(f"{context} uses forbidden key: {key}")

    require_type(manifest, "manifest", dict)
    manifest_keys = {
        "schema_version",
        "identity",
        "render",
        "palette",
        "world",
        "camera",
        "lights",
        "objects",
        "materials",
        "animation",
        "audio_binding",
        "output",
    }
    if set(manifest.keys()) != manifest_keys:
        missing = manifest_keys - set(manifest.keys())
        extra = set(manifest.keys()) - manifest_keys
        if missing:
            raise ValueError("manifest missing keys: " + ",".join(sorted(missing)))
        if extra:
            raise ValueError("manifest has unknown keys: " + ",".join(sorted(extra)))

    identity = manifest["identity"]
    render = manifest["render"]
    palette = manifest["palette"]
    world = manifest["world"]
    camera = manifest["camera"]
    lights = manifest["lights"]
    objects = manifest["objects"]
    materials = manifest["materials"]
    animation = manifest["animation"]
    audio_binding = manifest["audio_binding"]
    output = manifest["output"]

    for key in ("id", "project_id", "revision", "music_candidate_id"):
        require_string(identity.get(key, ""), f"identity.{key}", min_length=1, max_length=64)

    require_string(manifest["schema_version"], "schema_version", min_length=8, max_length=64)
    must_exist(render, "renderer")
    if render["renderer"] not in ("BLENDER_EEVEE", "BLENDER_CYCLES"):
        raise ValueError("unsupported renderer")
    require_int(render["width"], "render.width", minimum=64, maximum=1920)
    require_int(render["height"], "render.height", minimum=64, maximum=1080)
    require_int(render["fps"], "render.fps", minimum=1, maximum=60)
    require_int(render["frame_start"], "render.frame_start", minimum=1, maximum=10000)
    require_int(render["frame_end"], "render.frame_end", minimum=2, maximum=10000)
    if render["frame_end"] <= render["frame_start"]:
        raise ValueError("render.frame_end must be greater than render.frame_start")
    require_int(render["seed"], "render.seed", minimum=0, maximum=2**31 - 1)

    for channel in ("ambient", "horizon", "accent"):
        require_color(palette[channel], f"palette.{channel}")
    require_number(palette["contrast"], "palette.contrast", minimum=0.0, maximum=3.0)

    require_color(world["horizon_color"], "world.horizon_color")
    require_number(world["ambient_strength"], "world.ambient_strength", minimum=0.0, maximum=1.0)

    require_string(camera["id"], "camera.id", min_length=1, max_length=64, pattern="[a-zA-Z0-9_-]+")
    if camera["type"] != "PERSP":
        raise ValueError("camera.type must be PERSP")
    require_vector3(camera["location"], "camera.location", minimum=-1000.0, maximum=1000.0)
    require_vector3(camera["rotation_euler"], "camera.rotation_euler", minimum=-6.28, maximum=6.28)
    require_number(camera["lens"], "camera.lens", minimum=15.0, maximum=120.0)

    if not isinstance(lights, list) or not lights:
        raise ValueError("lights must be a non-empty list")
    if not isinstance(materials, list) or not materials:
        raise ValueError("materials must be a non-empty list")
    if not isinstance(objects, list) or not objects:
        raise ValueError("objects must be a non-empty list")

    material_ids = set()
    for material in materials:
        if not isinstance(material, dict):
            raise ValueError("material must be object")
        expected = {"id", "name", "type", "base_color", "metallic", "roughness", "emission", "emission_strength"}
        if set(material.keys()) - expected or not expected.issubset(material.keys()):
            unknown = ", ".join(sorted(set(material.keys()) - expected))
            missing = ", ".join(sorted(expected - set(material.keys())))
            if unknown:
                raise ValueError(f"material has unknown keys: {unknown}")
            if missing:
                raise ValueError(f"material missing keys: {missing}")
        for key in ("name", "type", "id"):
            forbid_key(material, "path", "material")
            require_string(material[key], f"material.{key}", min_length=1, max_length=64)
        material_ids.add(material["id"])
        if material["type"] not in ("PRINCIPLED", "LAMBERT", "SHADERLESS"):
            raise ValueError("material.type unsupported")
        require_color(material["base_color"], "material.base_color")
        require_number(material["metallic"], "material.metallic", 0.0, 1.0)
        require_number(material["roughness"], "material.roughness", 0.0, 1.0)
        if material["emission"] is not None:
            require_color(material["emission"], "material.emission")
            require_number(material["emission_strength"], "material.emission_strength", 0.0, 10.0)
        forbid_key(material, "nodes", "material")
        forbid_key(material, "driver", "material")

    for obj in objects:
        if not isinstance(obj, dict):
            raise ValueError("object must be object")
        required = {"id", "type", "location", "rotation_euler", "scale", "material"}
        if not required.issubset(obj.keys()):
            missing = ", ".join(sorted(required - set(obj.keys())))
            raise ValueError(f"object missing keys: {missing}")
        extra = set(obj.keys()) - required
        if extra:
            raise ValueError(f"object has unknown keys: {','.join(sorted(extra))}")
        require_string(obj["id"], "object.id", min_length=1, max_length=64, pattern="[a-zA-Z0-9_-]+")
        if obj["type"] not in ("CUBE", "PLANE", "UV_SPHERE", "ICO_SPHERE", "CIRCLE", "CYLINDER", "TORUS"):
            raise ValueError("object.type unsupported")
        require_vector3(obj["location"], "object.location", -1000.0, 1000.0)
        require_vector3(obj["rotation_euler"], "object.rotation_euler", -6.28, 6.28)
        require_vector3(obj["scale"], "object.scale", 0.05, 25.0)
        if obj["material"] not in material_ids:
            raise ValueError(f"object references unknown material: {obj['material']}")
        forbid_key(obj, "asset_path", "object")

    for light in lights:
        required = {"id", "type", "location", "energy", "color"}
        if not required.issubset(light.keys()):
            missing = ", ".join(sorted(required - set(light.keys())))
            raise ValueError(f"light missing keys: {missing}")
        forbid_key(light, "addon", "light")
        require_string(light["id"], "light.id", min_length=1, max_length=64, pattern="[a-zA-Z0-9_-]+")
        if light["type"] not in ("POINT", "SUN", "SPOT", "AREA"):
            raise ValueError("light.type unsupported")
        require_vector3(light["location"], "light.location", -1000.0, 1000.0)
        require_number(light["energy"], "light.energy", 0.1, 100000.0)
        require_color(light["color"], "light.color")
        if "nodes" in light or "driver" in light:
            raise ValueError("light uses forbidden key")
        if not ("import" not in json.dumps(light)):
            raise ValueError("light has forbidden token")

    required_animation_parts = {"objects", "materials", "camera", "lights", "world"}
    if set(animation.keys()) != required_animation_parts:
        missing = required_animation_parts - set(animation.keys())
        extra = set(animation.keys()) - required_animation_parts
        if missing:
            raise ValueError("animation missing keys: " + ",".join(sorted(missing)))
        if extra:
            raise ValueError("animation unknown keys: " + ",".join(sorted(extra)))

    for section, ids in (
        ("objects", {obj["id"] for obj in objects}),
        ("materials", material_ids),
        ("camera", {camera["id"]}),
        ("lights", {entry["id"] for entry in lights}),
        ("world", {"world"}),
    ):
        for channel in animation[section]:
            required = {"target_id", "property", "frames", "values", "interpolation"}
            if set(channel.keys()) != required:
                missing = ", ".join(sorted(required - set(channel.keys())))
                extra = ", ".join(sorted(set(channel.keys()) - required))
                if missing:
                    raise ValueError(f"animation channel missing keys: {missing}")
                if extra:
                    raise ValueError(f"animation channel has unknown keys: {extra}")
            if channel["target_id"] not in ids:
                raise ValueError(f"animation references unknown target id: {channel['target_id']}")
            if channel["property"] not in (
                "location",
                "rotation_euler",
                "scale",
                "lens",
                "energy",
                "horizon_color",
                "emission_strength",
                "metallic",
                "roughness",
            ):
                raise ValueError(f"animation property unsupported: {channel['property']}")
            if channel["interpolation"] not in ("LINEAR", "BEZIER", "CONSTANT"):
                raise ValueError("animation interpolation unsupported")
            if len(channel["frames"]) != len(channel["values"]):
                raise ValueError("animation channel must have same frame/value length")
            for frame in channel["frames"]:
                if not isinstance(frame, int) or not (render["frame_start"] <= frame <= render["frame_end"]):
                    raise ValueError("animation frame range out of bounds")
            for value in channel["values"]:
                vector_property = channel["property"] in ("location", "rotation_euler", "scale", "horizon_color")
                if vector_property:
                    if not isinstance(value, list) or len(value) != 3:
                        raise ValueError("animation vector property requires three numeric values")
                    minimum, maximum = (0.0, 1.0) if channel["property"] == "horizon_color" else (-1000.0, 1000.0)
                    for scalar in value:
                        require_number(scalar, "animation scalar", minimum, maximum)
                else:
                    if isinstance(value, list):
                        raise ValueError("animation scalar property cannot use a vector")
                    minimum, maximum = {
                        "lens": (1.0, 300.0),
                        "energy": (0.0, 200000.0),
                    }.get(channel["property"], (-1000.0, 1000.0))
                    require_number(value, "animation scalar", minimum, maximum)

    if not isinstance(audio_binding, dict) or set(audio_binding.keys()) != {"enabled", "tracks"}:
        raise ValueError("audio_binding must contain enabled and tracks")
    if not isinstance(audio_binding["tracks"], list):
        raise ValueError("audio_binding.tracks must be a list")
    if type(audio_binding["enabled"]) is not bool:
        raise ValueError("audio_binding.enabled must be bool")
    audio_targets = {
        "object": {obj["id"] for obj in objects},
        "material": material_ids,
        "camera": {camera["id"]},
        "light": {entry["id"] for entry in lights},
        "world": {"world"},
    }
    for track in audio_binding["tracks"]:
        if not isinstance(track, dict):
            raise ValueError("audio track must be object")
        required = {"target_type", "target_id", "property", "curve", "gain", "offset"}
        if set(track.keys()) != required:
            missing = ", ".join(sorted(required - set(track.keys())))
            if missing:
                raise ValueError(f"audio track missing keys: {missing}")
            extra = ", ".join(sorted(set(track.keys()) - required))
            if extra:
                raise ValueError(f"audio track unknown keys: {extra}")
        if track["target_type"] not in audio_targets:
            raise ValueError("audio target_type unsupported")
        if track["target_id"] not in audio_targets[track["target_type"]]:
            raise ValueError("audio target_id unsupported")
        if track["property"] not in (
            "location",
            "rotation_euler",
            "scale",
            "lens",
            "energy",
            "horizon_color",
            "emission_strength",
            "metallic",
            "roughness",
        ):
            raise ValueError("audio property unsupported")
        if track["curve"] not in ("kick", "low_band", "mid_band", "high_band", "energy"):
            raise ValueError("audio curve unsupported")
        require_number(track["gain"], "audio gain", 0.0, 5.0)
        require_int(track["offset"], "audio offset")
    require_file_name(output["blend_name"], "output.blend_name")
    require_file_name(output["still_name"], "output.still_name")
    require_int(output.get("still_frame", 1), "output.still_frame", minimum=1, maximum=render["frame_end"])

    if output["retention"] not in ("preview_only", "full_candidate"):
        raise ValueError("output retention unsupported")

    return manifest


def build_material_collection(material_spec):
    created = {}
    for item in sorted(material_spec, key=lambda entry: entry["id"]):
        if item["type"] in ("PRINCIPLED", "LAMBERT", "SHADERLESS"):
            material = bpy.data.materials.new(name=item["id"])
            material.use_nodes = True
            material.diffuse_color = tuple(item["base_color"]) + (1.0,)
            principled = material.node_tree.nodes.get("Principled BSDF")
            if principled is None:
                raise ValueError("trusted Principled BSDF node is unavailable")
            principled.inputs["Base Color"].default_value = tuple(item["base_color"]) + (1.0,)
            principled.inputs["Metallic"].default_value = item["metallic"]
            principled.inputs["Roughness"].default_value = item["roughness"]
            emission = item.get("emission")
            if emission is not None:
                principled.inputs["Emission Color"].default_value = tuple(emission) + (1.0,)
                principled.inputs["Emission Strength"].default_value = item["emission_strength"]
            created[item["id"]] = material
        else:
            raise ValueError(f"unsupported material type: {item['type']}")
    return created


def build_lights(specs, collection):
    for item in sorted(specs, key=lambda entry: entry["id"]):
        data = bpy.data.lights.new(name=item["id"], type=item["type"])
        data.energy = item["energy"]
        data.color = tuple(item["color"])
        light = bpy.data.objects.new(item["id"], data)
        light.location = item["location"]
        collection.objects.link(light)


def build_objects(specs, materials):
    for item in sorted(specs, key=lambda entry: entry["id"]):
        if item["type"] == "CUBE":
            bpy.ops.mesh.primitive_cube_add()
        elif item["type"] == "PLANE":
            bpy.ops.mesh.primitive_plane_add()
        elif item["type"] == "UV_SPHERE":
            bpy.ops.mesh.primitive_uv_sphere_add()
        elif item["type"] == "ICO_SPHERE":
            bpy.ops.mesh.primitive_ico_sphere_add()
        elif item["type"] == "CIRCLE":
            bpy.ops.mesh.primitive_circle_add()
        elif item["type"] == "CYLINDER":
            bpy.ops.mesh.primitive_cylinder_add()
        elif item["type"] == "TORUS":
            bpy.ops.mesh.primitive_torus_add()
        obj = bpy.context.object
        obj.name = item["id"]
        obj.location = item["location"]
        obj.rotation_euler = item["rotation_euler"]
        obj.scale = item["scale"]
        obj.data.materials.append(materials[item["material"]])
        if item["type"] in ("UV_SPHERE", "ICO_SPHERE", "CYLINDER", "TORUS"):
            for polygon in obj.data.polygons:
                polygon.use_smooth = True
        if item["type"] in ("CUBE", "CYLINDER"):
            bevel = obj.modifiers.new(name="SoulBevel", type="BEVEL")
            bevel.width = 0.06
            bevel.segments = 3


def set_action_interpolation(owner, interpolation):
    animation_data = getattr(owner, "animation_data", None)
    action = animation_data.action if animation_data else None
    if action is None:
        return
    for layer in action.layers:
        for strip in layer.strips:
            if strip.type != "KEYFRAME":
                continue
            for channelbag in strip.channelbags:
                for fcurve in channelbag.fcurves:
                    for point in fcurve.keyframe_points:
                        point.interpolation = interpolation


def apply_animation(manifest):
    camera_id = manifest["camera"]["id"]
    for section, entries in manifest["animation"].items():
        for entry in sorted(entries, key=lambda item: (item["target_id"], item["property"], item["frames"][0])):
            if section == "materials":
                target = bpy.data.materials.get(entry["target_id"])
            elif section == "world":
                target = bpy.context.scene.world
            else:
                target = bpy.data.objects.get(camera_id if section == "camera" else entry["target_id"])
            if target is None:
                raise ValueError(f"animation target is unavailable: {entry['target_id']}")
            for frame, value in zip(entry["frames"], entry["values"]):
                if entry["property"] in ("location", "rotation_euler", "scale"):
                    setattr(target, entry["property"], value)
                    target.keyframe_insert(data_path=entry["property"], frame=frame)
                elif section == "camera" and entry["property"] == "lens":
                    target.data.lens = float(value)
                    target.data.keyframe_insert(data_path="lens", frame=frame)
                elif section == "lights" and entry["property"] == "energy":
                    target.data.energy = float(value)
                    target.data.keyframe_insert(data_path="energy", frame=frame)
                elif section == "materials" and entry["property"] in ("emission_strength", "metallic", "roughness"):
                    principled = target.node_tree.nodes.get("Principled BSDF")
                    input_name = {
                        "emission_strength": "Emission Strength",
                        "metallic": "Metallic",
                        "roughness": "Roughness",
                    }[entry["property"]]
                    principled.inputs[input_name].default_value = float(value)
                    principled.inputs[input_name].keyframe_insert(data_path="default_value", frame=frame)
                    action_owner = principled.id_data
                elif section == "world" and entry["property"] == "horizon_color":
                    target.color = value
                    background = target.node_tree.nodes.get("Background")
                    if background is None:
                        raise ValueError("trusted World Background node is unavailable")
                    background.inputs["Color"].default_value = tuple(value) + (1.0,)
                    background.inputs["Color"].keyframe_insert(data_path="default_value", frame=frame)
                    action_owner = background.id_data
                else:
                    raise ValueError(f"unsupported trusted animation mapping: {section}.{entry['property']}")

            if section not in ("materials", "world"):
                action_owner = target.data if section in ("camera", "lights") else target
            set_action_interpolation(action_owner, entry["interpolation"])


def clear_scene():
    for item in list(bpy.data.objects):
        bpy.data.objects.remove(item, do_unlink=True)
    for item in list(bpy.data.materials):
        bpy.data.materials.remove(item, do_unlink=True)
    for item in list(bpy.data.lights):
        bpy.data.lights.remove(item, do_unlink=True)


def run(manifest, blend_path, still_path, still_frame):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = manifest["render"]["renderer"]
    scene.render.resolution_x = manifest["render"]["width"]
    scene.render.resolution_y = manifest["render"]["height"]
    scene.render.fps = manifest["render"]["fps"]
    scene.frame_start = manifest["render"]["frame_start"]
    scene.frame_end = manifest["render"]["frame_end"]

    world = bpy.data.worlds.new("SoulWorld")
    scene.world = world
    world.color = tuple(manifest["world"]["horizon_color"])
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is None:
        raise ValueError("trusted World Background node is unavailable")
    background.inputs["Color"].default_value = tuple(manifest["world"]["horizon_color"]) + (1.0,)
    background.inputs["Strength"].default_value = manifest["world"]["ambient_strength"]
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = still_path or ""

    # Camera
    camera_data = bpy.data.cameras.new(manifest["camera"]["id"])
    camera_data.lens = manifest["camera"]["lens"]
    camera = bpy.data.objects.new(manifest["camera"]["id"], camera_data)
    camera.location = manifest["camera"]["location"]
    camera.rotation_euler = manifest["camera"]["rotation_euler"]
    bpy.context.scene.collection.objects.link(camera)
    scene.camera = camera

    materials = build_material_collection(manifest["materials"])
    build_lights(manifest["lights"], bpy.context.scene.collection)
    build_objects(manifest["objects"], materials)
    apply_animation(manifest)

    bpy.ops.wm.save_as_mainfile(filepath=blend_path, check_existing=False)
    scene.frame_set(still_frame)
    if still_path:
        scene.render.image_settings.file_format = "PNG"
        bpy.context.scene.render.filepath = still_path
        bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    with open(args.manifest, "r", encoding="utf-8") as stream:
        manifest = json.load(stream)
    manifest = validate_manifest(manifest)

    if args.dry_run:
        normalized = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        print("SOUL_SCENE_ADAPTER_DRYRUN=" + normalized)
        return 0

    if not args.still_path:
        raise ValueError("--still-path is required unless --dry-run is set")

    # Keep safe names in manifest; command paths remain explicit process arguments.
    require_file_name(manifest["output"]["blend_name"], "output.blend_name")
    require_file_name(manifest["output"]["still_name"], "output.still_name")

    blend_path = os.path.abspath(args.blend_path)
    still_path = os.path.abspath(args.still_path)
    manifest["output"]["blend_name"] = os.path.basename(blend_path)
    manifest["output"]["still_name"] = os.path.basename(still_path)

    global bpy
    import bpy  # local import keeps py_compile lightweight and allows structural checks.

    run(manifest, blend_path, still_path, int(args.frame or manifest["output"]["still_frame"]))
    frame_count = manifest["render"]["frame_end"] - manifest["render"]["frame_start"] + 1
    print("SOUL_SCENE_ADAPTER_RUN=" + json.dumps({"blend_path": blend_path, "still_path": still_path, "frames": frame_count, "objects": len(manifest["objects"])}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
