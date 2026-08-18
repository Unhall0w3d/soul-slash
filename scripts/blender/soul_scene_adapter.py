#!/usr/bin/env python3
"""Bounded Blender scene adapter for Soul scene manifests.

This script validates a closed manifest, applies a bounded look profile
(surface / atmosphere / camera / glow / grade), and renders/exports the
blend and still image deterministically.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys


LOOK_DEFAULTS = {
    "surface": "clean",
    "atmosphere": "none",
    "camera": "crisp",
    "glow": "none",
    "grade": "neutral",
}
LOOK_SURFACES = {"clean", "organic", "crystalline", "machined"}
LOOK_ATMOSPHERES = {"none", "mist", "void_haze"}
LOOK_CAMERAS = {"crisp", "subtle_dof", "cinematic_dof"}
LOOK_GLOWS = {"none", "soft", "signal"}
LOOK_GRADES = {"neutral", "cinematic", "high_contrast"}
ORGANIC_ARCHETYPES = {"willow_tree", "mushroom_cluster"}
WILLOW_MATERIAL_ROLES = {"bark", "foliage"}
MUSHROOM_MATERIAL_ROLES = {"stem", "cap", "gill"}
WILLOW_PARAMETER_KEYS = {"branch_depth", "primary_branches", "strands_per_branch", "leaf_density", "trunk_segments", "sway"}
MUSHROOM_PARAMETER_KEYS = {"count", "cap_profile", "gill_segments", "spread", "height_variation"}
WILLOW_SWAY_PRESETS = {"none", "restrained", "windborne"}
MUSHROOM_CAP_PROFILES = {"bell", "convex", "conical", "flat"}
CURATED_ASSET_IDS = {"island_tree_01", "boulder_01"}
CURATED_ASSET_OBJECTS = {"island_tree_01": "island_tree_01_LOD1", "boulder_01": "boulder_01_LOD1"}
COMPOSITION_PRESETS = {"none", "orbital_campfire_study"}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--blend-path", required=True)
    parser.add_argument("--still-path", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--frame", type=int, default=1)
    parser.add_argument("--asset-root", default="")
    parser.add_argument("--asset-registry", default="")
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
    require_string(value, label, 1, 80, r"[A-Za-z0-9._-]+")
    if "/" in value or "\\" in value:
        raise ValueError(f"{label} must be file name only")


def get_node_input(node, *names):
    for name in names:
        if name in node.inputs:
            return node.inputs[name]
        found = node.inputs.get(name)
        if found is not None:
            return found
    return None


def get_node_output(node, *names):
    for name in names:
        if name in node.outputs:
            return node.outputs[name]
        found = node.outputs.get(name)
        if found is not None:
            return found
    return None


def set_input_value(node, input_name, value):
    input_port = get_node_input(node, input_name)
    if input_port is None:
        return
    if input_port.enabled:
        input_port.default_value = value


def safe_link(node_tree, from_port, to_port):
    if from_port is None or to_port is None:
        return False
    node_tree.links.new(from_port, to_port)
    return True


def remove_nodes_with_prefix(collection, prefix):
    for node in list(collection):
        if node.name.startswith(prefix):
            collection.remove(node)


def reject_unknown(data, allowed, label):
    extras = set(data.keys()) - set(allowed)
    if extras:
        raise ValueError(f"{label} has unknown keys: {','.join(sorted(extras))}")
    missing = set(allowed) - set(data.keys())
    if missing:
        raise ValueError(f"{label} missing keys: {','.join(sorted(missing))}")


def forbid_key(data, key, label):
    if key in data:
        raise ValueError(f"{label} uses forbidden key: {key}")


def validate_manifest(manifest):
    require_type(manifest, "manifest", dict)

    top_level = {
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
        "look",
        "organics",
        "curated_assets",
        "composition",
    }
    required_top_level = top_level - {"look", "organics", "curated_assets", "composition"}
    if not required_top_level.issubset(manifest.keys()) or not set(manifest.keys()).issubset(top_level):
        reject_unknown(manifest, top_level, "manifest")
    manifest.setdefault("look", {})
    manifest.setdefault("organics", [])
    manifest.setdefault("curated_assets", [])
    manifest.setdefault("composition", {"preset": "none"})

    identity = manifest["identity"]
    render = manifest["render"]
    palette = manifest["palette"]
    world = manifest["world"]
    camera = manifest["camera"]
    lights = manifest["lights"]
    materials = manifest["materials"]
    objects = manifest["objects"]
    animation = manifest["animation"]
    audio_binding = manifest["audio_binding"]
    output = manifest["output"]
    look = manifest["look"]
    organics = manifest["organics"]
    curated_assets = manifest["curated_assets"]
    composition = manifest["composition"]

    for key in ("id", "project_id", "revision", "music_candidate_id"):
        require_string(identity[key], f"identity.{key}", min_length=1, max_length=64)

    require_string(manifest["schema_version"], "schema_version", 1, 64)

    # Defaults preserve compatibility with manifests that predate the look map;
    # unknown look keys remain invalid.
    look = dict(LOOK_DEFAULTS, **(look if isinstance(look, dict) else {}))
    reject_unknown(look, LOOK_DEFAULTS.keys(), "look")
    if look["surface"] not in LOOK_SURFACES:
        raise ValueError("look.surface invalid")
    if look["atmosphere"] not in LOOK_ATMOSPHERES:
        raise ValueError("look.atmosphere invalid")
    if look["camera"] not in LOOK_CAMERAS:
        raise ValueError("look.camera invalid")
    if look["glow"] not in LOOK_GLOWS:
        raise ValueError("look.glow invalid")
    if look["grade"] not in LOOK_GRADES:
        raise ValueError("look.grade invalid")
    manifest["look"] = look

    if render["renderer"] not in ("BLENDER_EEVEE", "BLENDER_CYCLES"):
        raise ValueError("unsupported renderer")
    require_int(render["width"], "render.width", 64, 1920)
    require_int(render["height"], "render.height", 64, 1080)
    require_int(render["fps"], "render.fps", 1, 60)
    require_int(render["frame_start"], "render.frame_start", 1, 10000)
    require_int(render["frame_end"], "render.frame_end", 2, 10000)
    require_int(render["seed"], "render.seed", 0, 2**31 - 1)
    if render["frame_end"] <= render["frame_start"]:
        raise ValueError("render.frame_end must be greater than frame_start")

    for channel in ("ambient", "horizon", "accent"):
        require_color(palette[channel], f"palette.{channel}")
    require_number(palette["contrast"], "palette.contrast", 0.0, 3.0)

    require_color(world["horizon_color"], "world.horizon_color")
    require_number(world["ambient_strength"], "world.ambient_strength", 0.0, 1.0)

    require_string(camera["id"], "camera.id", 1, 64, r"[A-Za-z0-9_-]+")
    if camera["type"] != "PERSP":
        raise ValueError("camera.type must be PERSP")
    require_vector3(camera["location"], "camera.location", -1000.0, 1000.0)
    require_vector3(camera["rotation_euler"], "camera.rotation_euler", -6.28, 6.28)
    require_number(camera["lens"], "camera.lens", 15.0, 120.0)

    if not isinstance(lights, list) or not lights:
        raise ValueError("lights must be a non-empty list")
    if not isinstance(materials, list) or not materials:
        raise ValueError("materials must be a non-empty list")
    if not isinstance(objects, list) or not objects:
        raise ValueError("objects must be a non-empty list")

    material_ids = set()
    for material in materials:
        if not isinstance(material, dict):
            raise ValueError("material must be map")
        keys = {"id", "name", "type", "base_color", "metallic", "roughness", "emission", "emission_strength"}
        reject_unknown(material, keys, "material")
        forbid_key(material, "path", "material")
        forbid_key(material, "script", "material")
        forbid_key(material, "nodes", "material")
        forbid_key(material, "driver", "material")
        for key in ("id", "name", "type"):
            require_string(material[key], f"material.{key}", 1, 64, r"[A-Za-z0-9_-]+" if key == "id" else None)
        if material["type"] not in ("PRINCIPLED", "LAMBERT", "SHADERLESS"):
            raise ValueError("material.type unsupported")
        require_color(material["base_color"], "material.base_color")
        require_number(material["metallic"], "material.metallic", 0.0, 1.0)
        require_number(material["roughness"], "material.roughness", 0.0, 1.0)
        if material["emission"] is not None:
            require_color(material["emission"], "material.emission")
            require_number(material["emission_strength"], "material.emission_strength", 0.0, 10.0)
        material_ids.add(material["id"])

    for obj in objects:
        if not isinstance(obj, dict):
            raise ValueError("object must be map")
        keys = {"id", "type", "location", "rotation_euler", "scale", "material"}
        reject_unknown(obj, keys, "object")
        forbid_key(obj, "asset_path", "object")
        require_string(obj["id"], "object.id", 1, 64, r"[A-Za-z0-9_-]+")
        if obj["type"] not in ("CUBE", "PLANE", "UV_SPHERE", "ICO_SPHERE", "CIRCLE", "CYLINDER", "TORUS"):
            raise ValueError("object.type unsupported")
        require_vector3(obj["location"], "object.location", -1000.0, 1000.0)
        require_vector3(obj["rotation_euler"], "object.rotation_euler", -6.28, 6.28)
        require_vector3(obj["scale"], "object.scale", 0.05, 25.0)
        if obj["material"] not in material_ids:
            raise ValueError(f"object references unknown material: {obj['material']}")

    validate_organics(organics, material_ids, {entry["id"] for entry in objects})
    validate_curated_assets(curated_assets, {entry["id"] for entry in objects}, {entry["id"] for entry in organics})
    reject_unknown(composition, {"preset"}, "composition")
    if composition["preset"] not in COMPOSITION_PRESETS:
        raise ValueError("composition.preset invalid")

    for light in lights:
        if not isinstance(light, dict):
            raise ValueError("light must be map")
        keys = {"id", "type", "location", "energy", "color"}
        reject_unknown(light, keys, "light")
        forbid_key(light, "driver", "light")
        forbid_key(light, "addon", "light")
        forbid_key(light, "nodes", "light")
        require_string(light["id"], "light.id", 1, 64, r"[A-Za-z0-9_-]+")
        if light["type"] not in ("POINT", "SUN", "SPOT", "AREA"):
            raise ValueError("light.type unsupported")
        require_vector3(light["location"], "light.location", -1000.0, 1000.0)
        require_number(light["energy"], "light.energy", 0.1, 100000.0)
        require_color(light["color"], "light.color")

    animation_required = {"objects", "materials", "camera", "lights", "world"}
    reject_unknown(animation, animation_required, "animation")
    for section, ids in (
        ("objects", {obj["id"] for obj in objects}),
        ("materials", material_ids),
        ("camera", {camera["id"]}),
        ("lights", {entry["id"] for entry in lights}),
        ("world", {"world"}),
    ):
        for channel in animation[section]:
            if not isinstance(channel, dict):
                raise ValueError("animation channel must be map")
            channel_keys = {"target_id", "property", "frames", "values", "interpolation"}
            reject_unknown(channel, channel_keys, f"animation.{section}")
            require_string(channel["target_id"], f"animation.{section}.target_id", 1, 64)
            if channel["target_id"] not in ids:
                raise ValueError(f"animation references unknown target: {channel['target_id']}")
            if channel["property"] not in ("location", "rotation_euler", "scale", "lens", "energy", "horizon_color", "emission_strength", "metallic", "roughness"):
                raise ValueError("animation property unsupported")
            if channel["interpolation"] not in ("LINEAR", "BEZIER", "CONSTANT"):
                raise ValueError("animation interpolation unsupported")
            frames = channel["frames"]
            values = channel["values"]
            if not isinstance(frames, list) or not isinstance(values, list):
                raise ValueError("animation frames/values must be arrays")
            if len(frames) != len(values) or not (1 <= len(frames) <= 512):
                raise ValueError("animation channel must be 1..512 entries and frames/values length match")
            if frames != sorted(frames):
                raise ValueError("animation frames must be non-decreasing")
            for index, frame in enumerate(frames):
                require_int(frame, f"animation.{section}.frames[{index}]", render["frame_start"], render["frame_end"])
            vector_property = channel["property"] in {"location", "rotation_euler", "scale", "horizon_color"}
            for value in values:
                if vector_property:
                    minimum, maximum = (0.0, 1.0) if channel["property"] == "horizon_color" else (-1000.0, 1000.0)
                    require_vector3(value, f"animation.{section}.value", minimum, maximum)
                else:
                    if isinstance(value, list):
                        raise ValueError("animation scalar values cannot be vectors")
                    min_val, max_val = (1.0, 300.0) if channel["property"] == "lens" else (0.0, 200000.0) if channel["property"] == "energy" else (-1000.0, 1000.0)
                    require_number(value, f"animation.{section}.value", min_val, max_val)

    reject_unknown(audio_binding, {"enabled", "tracks"}, "audio_binding")
    if type(audio_binding["enabled"]) is not bool:
        raise ValueError("audio_binding.enabled must be bool")
    if not isinstance(audio_binding["tracks"], list):
        raise ValueError("audio_binding.tracks must be list")

    audio_targets = {
        "object": {obj["id"] for obj in objects},
        "material": material_ids,
        "camera": {camera["id"]},
        "light": {entry["id"] for entry in lights},
        "world": {"world"},
    }
    for track in audio_binding["tracks"]:
        if not isinstance(track, dict):
            raise ValueError("audio track must be map")
        track_keys = {"target_type", "target_id", "property", "curve", "gain", "offset"}
        reject_unknown(track, track_keys, "audio_binding.track")
        require_string(track["target_type"], "audio.track.target_type", 1, 20)
        if track["target_type"] not in audio_targets:
            raise ValueError("audio target_type unsupported")
        if track["target_id"] not in audio_targets[track["target_type"]]:
            raise ValueError("audio target_id unsupported")
        if track["property"] not in ("location", "rotation_euler", "scale", "lens", "energy", "horizon_color", "emission_strength", "metallic", "roughness"):
            raise ValueError("audio property unsupported")
        if track["curve"] not in ("kick", "low_band", "mid_band", "high_band", "energy"):
            raise ValueError("audio curve unsupported")
        require_number(track["gain"], "audio gain", 0.0, 5.0)
        require_int(track["offset"], "audio offset", 0, 5000)

    reject_unknown(output, {"blend_name", "still_name", "still_frame", "retention"}, "output")
    require_file_name(output["blend_name"], "output.blend_name")
    require_file_name(output["still_name"], "output.still_name")
    require_int(output.get("still_frame", 1), "output.still_frame", 1, render["frame_end"])
    if not output["blend_name"].endswith(".blend"):
        raise ValueError("output.blend_name must end in .blend")
    if not output["still_name"].endswith(".png"):
        raise ValueError("output.still_name must end in .png")
    if output["retention"] not in ("preview_only", "full_candidate"):
        raise ValueError("output retention unsupported")

    return manifest


def validate_organics(organics, material_ids, object_ids):
    """Validate A7's closed, repository-owned procedural construction vocabulary."""
    if not isinstance(organics, list):
        raise ValueError("organics must be a list")
    if len(organics) > 16:
        raise ValueError("organics exceeds maximum of 16")

    organic_ids = set()
    for organic in organics:
        if not isinstance(organic, dict):
            raise ValueError("organic must be map")
        keys = {"id", "archetype", "location", "rotation_euler", "scale", "seed", "materials", "parameters"}
        reject_unknown(organic, keys, "organic")
        for forbidden in ("path", "paths", "script", "scripts", "driver", "addon", "nodes", "asset", "asset_path", "import"):
            forbid_key(organic, forbidden, "organic")
        require_string(organic["id"], "organic.id", 2, 64, r"[A-Za-z0-9_-]+")
        if organic["id"] in organic_ids:
            raise ValueError(f"duplicate organic id: {organic['id']}")
        if organic["id"] in object_ids:
            raise ValueError("organic.id conflicts with object id")
        organic_ids.add(organic["id"])
        if organic["archetype"] not in ORGANIC_ARCHETYPES:
            raise ValueError("organic.archetype unsupported")
        require_vector3(organic["location"], "organic.location", -1000.0, 1000.0)
        require_vector3(organic["rotation_euler"], "organic.rotation_euler", -6.28, 6.28)
        require_vector3(organic["scale"], "organic.scale", 0.05, 25.0)
        require_int(organic["seed"], "organic.seed", 0, 2**31 - 1)

        material_roles = WILLOW_MATERIAL_ROLES if organic["archetype"] == "willow_tree" else MUSHROOM_MATERIAL_ROLES
        materials = organic["materials"]
        if not isinstance(materials, dict):
            raise ValueError("organic.materials must be map")
        reject_unknown(materials, material_roles, "organic.materials")
        for role, material_id in materials.items():
            require_string(material_id, f"organic.materials.{role}", 2, 64, r"[A-Za-z0-9_-]+")
            if material_id not in material_ids:
                raise ValueError(f"organic material unknown: {material_id}")

        parameters = organic["parameters"]
        if not isinstance(parameters, dict):
            raise ValueError("organic.parameters must be map")
        if organic["archetype"] == "willow_tree":
            reject_unknown(parameters, WILLOW_PARAMETER_KEYS, "organic.parameters")
            require_int(parameters["branch_depth"], "organic.parameters.branch_depth", 2, 4)
            require_int(parameters["primary_branches"], "organic.parameters.primary_branches", 4, 10)
            require_int(parameters["strands_per_branch"], "organic.parameters.strands_per_branch", 3, 9)
            require_int(parameters["leaf_density"], "organic.parameters.leaf_density", 2, 8)
            require_int(parameters["trunk_segments"], "organic.parameters.trunk_segments", 5, 12)
            if parameters["sway"] not in WILLOW_SWAY_PRESETS:
                raise ValueError("organic.parameters.sway unsupported")
        else:
            reject_unknown(parameters, MUSHROOM_PARAMETER_KEYS, "organic.parameters")
            require_int(parameters["count"], "organic.parameters.count", 3, 12)
            if parameters["cap_profile"] not in MUSHROOM_CAP_PROFILES:
                raise ValueError("organic.parameters.cap_profile unsupported")
            require_int(parameters["gill_segments"], "organic.parameters.gill_segments", 12, 40)
            require_number(parameters["spread"], "organic.parameters.spread", 0.5, 5.0)
            require_number(parameters["height_variation"], "organic.parameters.height_variation", 0.0, 0.8)


def validate_curated_assets(entries, object_ids, organic_ids):
    if not isinstance(entries, list):
        raise ValueError("curated_assets must be a list")
    if len(entries) > 16:
        raise ValueError("curated_assets exceeds maximum of 16")
    seen = set(object_ids) | set(organic_ids)
    keys = {"id", "asset_id", "location", "rotation_euler", "scale"}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("curated_asset must be a map")
        reject_unknown(entry, keys, "curated_asset")
        require_string(entry["id"], "curated_asset.id", 2, 64, r"[A-Za-z0-9_-]+")
        if entry["id"] in seen:
            raise ValueError("curated_asset.id conflicts with scene id")
        seen.add(entry["id"])
        if entry["asset_id"] not in CURATED_ASSET_IDS:
            raise ValueError("curated_asset.asset_id invalid")
        require_vector3(entry["location"], "curated_asset.location")
        require_vector3(entry["rotation_euler"], "curated_asset.rotation_euler", -6.29, 6.29)
        require_vector3(entry["scale"], "curated_asset.scale", 0.01, 100.0)


def build_material_collection(material_spec):
    created = {}
    for item in sorted(material_spec, key=lambda entry: entry["id"]):
        material = bpy.data.materials.new(name=item["id"])
        material.use_nodes = True
        material.diffuse_color = tuple(item["base_color"]) + (1.0,)
        principled = material.node_tree.nodes.get("Principled BSDF")
        if principled is None:
            raise ValueError("trusted Principled BSDF node is unavailable")
        principled.inputs["Base Color"].default_value = tuple(item["base_color"]) + (1.0,)
        principled.inputs["Metallic"].default_value = item["metallic"]
        principled.inputs["Roughness"].default_value = item["roughness"]
        if item["emission"] is not None:
            principled.inputs["Emission Color"].default_value = tuple(item["emission"]) + (1.0,)
            principled.inputs["Emission Strength"].default_value = item["emission_strength"]
        created[item["id"]] = material
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
        else:
            raise ValueError(f"unsupported object type: {item['type']}")

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


def create_organic_mesh(name, vertices, faces, material, parent):
    """Create one trusted mesh from bounded in-memory geometry only."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    return obj


def append_tapered_tube(vertices, faces, centers, radii, sides=8):
    """Append a bounded ring mesh suitable for curved trunks, roots, and stems."""
    import math

    start = len(vertices)
    for center, radius in zip(centers, radii):
        for side in range(sides):
            angle = 2.0 * math.pi * side / sides
            vertices.append((center[0] + radius * math.cos(angle), center[1] + radius * math.sin(angle), center[2]))
    for ring in range(len(centers) - 1):
        for side in range(sides):
            next_side = (side + 1) % sides
            first = start + ring * sides + side
            second = start + ring * sides + next_side
            third = start + (ring + 1) * sides + next_side
            fourth = start + (ring + 1) * sides + side
            faces.append((first, second, third, fourth))
    faces.append(tuple(reversed(range(start, start + sides))))
    end = start + (len(centers) - 1) * sides
    faces.append(tuple(range(end, end + sides)))


def add_curve_spline(curve_data, points):
    spline = curve_data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"


def add_willow_sway(root, scene, preset):
    """Keyframe a single bounded, seamless loop; no drivers or background work."""
    if preset == "none":
        return
    amplitude = 0.025 if preset == "restrained" else 0.075
    start = scene.frame_start
    middle = start + (scene.frame_end - start) // 2
    end = scene.frame_end
    for frame, angle in ((start, 0.0), (middle, amplitude), (end, 0.0)):
        root.rotation_euler[1] = angle
        root.keyframe_insert(data_path="rotation_euler", index=1, frame=frame)


def build_willow_tree(organic, materials, scene):
    """Trusted A7 willow builder: tapered roots/trunk, curved hierarchy, and one leaf mesh."""
    import math
    import random

    params = organic["parameters"]
    rng = random.Random(organic["seed"])
    root = bpy.data.objects.new(organic["id"], None)
    root.empty_display_type = "PLAIN_AXES"
    root.location = organic["location"]
    root.rotation_euler = organic["rotation_euler"]
    root.scale = organic["scale"]
    root["soul_organic_archetype"] = "willow_tree"
    root["soul_organic_builder"] = "trusted_a7_willow"
    bpy.context.scene.collection.objects.link(root)

    trunk_vertices, trunk_faces = [], []
    trunk_height = 2.8 + rng.uniform(-0.20, 0.20)
    trunk_centers = []
    for index in range(params["trunk_segments"]):
        fraction = index / (params["trunk_segments"] - 1)
        trunk_centers.append((0.10 * math.sin(fraction * 3.1), 0.08 * math.cos(fraction * 2.4), trunk_height * fraction))
    trunk_radii = [0.48 * (1.0 - 0.68 * index / (params["trunk_segments"] - 1)) for index in range(params["trunk_segments"])]
    append_tapered_tube(trunk_vertices, trunk_faces, trunk_centers, trunk_radii)
    for root_index in range(5):
        angle = 2.0 * math.pi * root_index / 5.0 + rng.uniform(-0.20, 0.20)
        reach = 1.35 + rng.uniform(0.0, 0.60)
        centers = [(0.0, 0.0, 0.12), (0.34 * math.cos(angle), 0.34 * math.sin(angle), 0.08),
                   (reach * math.cos(angle), reach * math.sin(angle), -0.04)]
        append_tapered_tube(trunk_vertices, trunk_faces, centers, (0.20, 0.12, 0.025), sides=6)
    create_organic_mesh(f"{organic['id']}_trunk_roots", trunk_vertices, trunk_faces, materials[organic["materials"]["bark"]], root)

    branch_data = bpy.data.curves.new(f"{organic['id']}_branches", type="CURVE")
    branch_data.dimensions = "3D"
    branch_data.resolution_u = 2
    branch_data.bevel_depth = 0.055
    branch_data.bevel_resolution = 2
    branch_obj = bpy.data.objects.new(f"{organic['id']}_branches", branch_data)
    branch_data.materials.append(materials[organic["materials"]["bark"]])
    bpy.context.scene.collection.objects.link(branch_obj)
    branch_obj.parent = root

    leaf_vertices, leaf_faces = [], []
    for primary in range(params["primary_branches"]):
        angle = 2.0 * math.pi * primary / params["primary_branches"] + rng.uniform(-0.22, 0.22)
        origin = trunk_centers[-1]
        direction = (math.cos(angle), math.sin(angle))
        terminal = origin
        branch_nodes = [origin]
        for depth in range(params["branch_depth"]):
            length = (0.85 - depth * 0.10) * rng.uniform(0.86, 1.12)
            rise = 0.20 - depth * 0.08
            end = (terminal[0] + direction[0] * length, terminal[1] + direction[1] * length, terminal[2] + rise)
            branch_nodes.append(end)
            terminal = end
            angle += rng.uniform(-0.38, 0.38)
            direction = (math.cos(angle), math.sin(angle))
        # One continuous curved primary limb avoids the jointed umbrella
        # silhouette of individual two-point branch segments.
        add_curve_spline(branch_data, tuple(branch_nodes))
        # Small deterministic forks make the crown read as a hierarchy rather
        # than a wheel of identical spokes, while remaining inside the closed
        # branch-depth and primary-branch bounds.
        for fork_index, fork_origin in enumerate(branch_nodes[1:-1], start=1):
            fork_angle = angle + (-1.0 if fork_index % 2 else 1.0) * rng.uniform(0.38, 0.72)
            fork_length = rng.uniform(0.48, 0.82)
            fork_end = (fork_origin[0] + math.cos(fork_angle) * fork_length,
                        fork_origin[1] + math.sin(fork_angle) * fork_length,
                        fork_origin[2] - rng.uniform(0.02, 0.18))
            fork_control = ((fork_origin[0] + fork_end[0]) * 0.5,
                            (fork_origin[1] + fork_end[1]) * 0.5,
                            fork_origin[2] + 0.16)
            add_curve_spline(branch_data, (fork_origin, fork_control, fork_end))
        for strand in range(params["strands_per_branch"]):
            strand_angle = angle + rng.uniform(-0.52, 0.52)
            strand_length = 1.0 + rng.uniform(0.25, 1.10)
            attachment = branch_nodes[1 + strand % (len(branch_nodes) - 1)]
            start = (attachment[0] + rng.uniform(-0.22, 0.22),
                     attachment[1] + rng.uniform(-0.22, 0.22),
                     attachment[2] + rng.uniform(-0.06, 0.10))
            middle = (start[0] + 0.18 * math.cos(strand_angle), start[1] + 0.18 * math.sin(strand_angle), start[2] - strand_length * 0.38)
            end = (middle[0] + 0.12 * math.cos(strand_angle), middle[1] + 0.12 * math.sin(strand_angle), start[2] - strand_length)
            add_curve_spline(branch_data, (start, middle, end))
            for leaf_index in range(params["leaf_density"] * 2):
                fraction = (leaf_index + 1) / (params["leaf_density"] * 2 + 1)
                center = tuple(start[axis] * (1.0 - fraction) + end[axis] * fraction for axis in range(3))
                width = 0.045 + rng.uniform(0.0, 0.035)
                height = 0.13 + rng.uniform(0.0, 0.06)
                # Two crossed, tapered blades keep the bounded combined mesh
                # legible from both frontal and oblique camera positions.  The
                # earlier single XY-facing quad became almost invisible when
                # viewed across the grove.
                offset = len(leaf_vertices)
                leaf_vertices.extend((
                    (center[0], center[1], center[2] + height * 0.18),
                    (center[0] - width, center[1], center[2] - height * 0.40),
                    (center[0], center[1], center[2] - height),
                    (center[0] + width, center[1], center[2] - height * 0.40),
                    (center[0], center[1], center[2] + height * 0.18),
                    (center[0], center[1] - width, center[2] - height * 0.40),
                    (center[0], center[1], center[2] - height),
                    (center[0], center[1] + width, center[2] - height * 0.40),
                ))
                leaf_faces.extend(((offset, offset + 1, offset + 2, offset + 3),
                                   (offset + 4, offset + 5, offset + 6, offset + 7)))
    create_organic_mesh(f"{organic['id']}_leaf_mesh", leaf_vertices, leaf_faces, materials[organic["materials"]["foliage"]], root)
    add_willow_sway(root, scene, params["sway"])


def cap_profile_points(profile):
    """Reviewed revolved profiles all include an outward overhang before the underside."""
    profiles = {
        "bell": ((0.04, 0.52), (0.38, 0.44), (0.84, 0.18), (1.08, -0.08), (0.72, -0.18)),
        "convex": ((0.04, 0.40), (0.42, 0.43), (0.90, 0.18), (1.10, -0.06), (0.74, -0.14)),
        "conical": ((0.04, 0.68), (0.46, 0.34), (0.92, 0.02), (1.08, -0.09), (0.70, -0.16)),
        "flat": ((0.06, 0.25), (0.50, 0.28), (0.95, 0.10), (1.09, -0.07), (0.73, -0.13)),
    }
    return profiles[profile]


def append_revolved_cap(vertices, faces, center, radius, profile, segments=16):
    import math

    start = len(vertices)
    points = cap_profile_points(profile)
    for radial, height in points:
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            vertices.append((center[0] + radius * radial * math.cos(angle), center[1] + radius * radial * math.sin(angle), center[2] + radius * height))
    for ring in range(len(points) - 1):
        for segment in range(segments):
            next_segment = (segment + 1) % segments
            first = start + ring * segments + segment
            second = start + ring * segments + next_segment
            third = start + (ring + 1) * segments + next_segment
            fourth = start + (ring + 1) * segments + segment
            faces.append((first, second, third, fourth))


def build_mushroom_cluster(organic, materials):
    """Trusted A7 mushroom builder: curved tapered stems, revolved caps, and radial gills."""
    import math
    import random

    params = organic["parameters"]
    rng = random.Random(organic["seed"])
    root = bpy.data.objects.new(organic["id"], None)
    root.empty_display_type = "SINGLE_ARROW"
    root.location = organic["location"]
    root.rotation_euler = organic["rotation_euler"]
    root.scale = organic["scale"]
    root["soul_organic_archetype"] = "mushroom_cluster"
    root["soul_organic_builder"] = "trusted_a7_mushroom"
    bpy.context.scene.collection.objects.link(root)

    stem_vertices, stem_faces, cap_vertices, cap_faces, gill_vertices, gill_faces = [], [], [], [], [], []
    for index in range(params["count"]):
        angle = 2.0 * math.pi * index / params["count"] + rng.uniform(-0.30, 0.30)
        radial = params["spread"] * math.sqrt(rng.random())
        x, y = radial * math.cos(angle), radial * math.sin(angle)
        height = 0.72 + rng.uniform(-params["height_variation"], params["height_variation"])
        height = max(0.28, height)
        radius = 0.20 + rng.uniform(-0.035, 0.075)
        lean = rng.uniform(-0.18, 0.18)
        centers = [(x + lean * (level / 5.0) ** 2, y + 0.06 * math.sin(level), height * level / 5.0) for level in range(6)]
        append_tapered_tube(stem_vertices, stem_faces, centers, [radius * (1.0 - 0.38 * level / 5.0) for level in range(6)], sides=8)
        cap_center = centers[-1]
        cap_radius = radius * rng.uniform(2.1, 3.4)
        append_revolved_cap(cap_vertices, cap_faces, cap_center, cap_radius, params["cap_profile"])
        underside_z = cap_center[2] - cap_radius * 0.13
        for gill in range(params["gill_segments"]):
            gill_angle = 2.0 * math.pi * gill / params["gill_segments"]
            perpendicular = (-math.sin(gill_angle) * cap_radius * 0.018, math.cos(gill_angle) * cap_radius * 0.018)
            inner = cap_radius * 0.18
            outer = cap_radius * 0.92
            a = (cap_center[0] + inner * math.cos(gill_angle), cap_center[1] + inner * math.sin(gill_angle), underside_z)
            b = (cap_center[0] + outer * math.cos(gill_angle), cap_center[1] + outer * math.sin(gill_angle), underside_z - cap_radius * 0.035)
            offset = len(gill_vertices)
            gill_vertices.extend(((a[0] + perpendicular[0], a[1] + perpendicular[1], a[2]), (a[0] - perpendicular[0], a[1] - perpendicular[1], a[2]),
                                  (b[0] - perpendicular[0], b[1] - perpendicular[1], b[2]), (b[0] + perpendicular[0], b[1] + perpendicular[1], b[2])))
            gill_faces.append((offset, offset + 1, offset + 2, offset + 3))
    create_organic_mesh(f"{organic['id']}_stems", stem_vertices, stem_faces, materials[organic["materials"]["stem"]], root)
    create_organic_mesh(f"{organic['id']}_caps", cap_vertices, cap_faces, materials[organic["materials"]["cap"]], root)
    create_organic_mesh(f"{organic['id']}_gills", gill_vertices, gill_faces, materials[organic["materials"]["gill"]], root)


def build_organics(specs, materials, scene):
    for organic in sorted(specs, key=lambda entry: entry["id"]):
        if organic["archetype"] == "willow_tree":
            build_willow_tree(organic, materials, scene)
        elif organic["archetype"] == "mushroom_cluster":
            build_mushroom_cluster(organic, materials)
        else:
            raise ValueError(f"unsupported organic archetype: {organic['archetype']}")


def load_curated_asset_map(asset_root, registry_path, required_ids):
    if not required_ids:
        return {}
    if not asset_root or not registry_path:
        raise ValueError("curated assets require trusted asset root and registry")
    asset_root = os.path.realpath(asset_root)
    registry_path = os.path.realpath(registry_path)
    if not os.path.isfile(registry_path) or os.path.islink(registry_path):
        raise ValueError("curated asset registry is invalid")
    with open(registry_path, "r", encoding="utf-8") as stream:
        registry = json.load(stream)
    if registry.get("schema_version") != 1:
        raise ValueError("curated asset registry schema is invalid")
    assets = {entry["id"]: entry for entry in registry.get("assets", [])}
    if set(assets) != CURATED_ASSET_IDS or not required_ids.issubset(assets):
        raise ValueError("curated asset registry identity is invalid")
    mapped = {}
    for asset_id in sorted(required_ids):
        blend_path = None
        for entry in assets[asset_id]["files"]:
            relative = entry["path"]
            candidate = os.path.realpath(os.path.join(asset_root, relative))
            if not candidate.startswith(asset_root + os.sep) or os.path.islink(candidate) or not os.path.isfile(candidate):
                raise ValueError(f"curated asset path is invalid: {asset_id}")
            if os.path.getsize(candidate) != entry["bytes"]:
                raise ValueError(f"curated asset size changed: {asset_id}")
            with open(candidate, "rb") as stream:
                actual = hashlib.sha256(stream.read()).hexdigest()
            if actual != entry["sha256"]:
                raise ValueError(f"curated asset digest changed: {asset_id}")
            if relative.endswith(".blend"):
                blend_path = candidate
        if not blend_path:
            raise ValueError(f"curated asset blend file is missing: {asset_id}")
        mapped[asset_id] = blend_path
    return mapped


def build_curated_assets(specs, asset_map, collection):
    loaded = {}
    for entry in sorted(specs, key=lambda item: item["id"]):
        asset_id = entry["asset_id"]
        if asset_id not in loaded:
            object_name = CURATED_ASSET_OBJECTS[asset_id]
            with bpy.data.libraries.load(asset_map[asset_id], link=False) as (source, target):
                if object_name not in source.objects:
                    raise ValueError(f"reviewed curated object is missing: {asset_id}")
                target.objects = [object_name]
            loaded[asset_id] = target.objects[0]
        source = loaded[asset_id]
        instance = source if not any(obj.get("soul_curated_asset") == asset_id for obj in collection.objects) else source.copy()
        if instance.name not in collection.objects:
            collection.objects.link(instance)
        instance.name = entry["id"]
        instance.location = entry["location"]
        instance.rotation_euler = entry["rotation_euler"]
        instance.scale = entry["scale"]
        instance["soul_curated_asset"] = asset_id
        instance["soul_asset_source"] = "Poly Haven CC0 1K"


def emission_material(name, color, strength):
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = tuple(color) + (1.0,)
    principled.inputs["Emission Color"].default_value = tuple(color) + (1.0,)
    principled.inputs["Emission Strength"].default_value = strength
    principled.inputs["Roughness"].default_value = 0.7
    return material


def build_star_field(scene, seed):
    import math
    import random

    rng = random.Random(seed + 9107)
    vertices, faces = [], []
    for index in range(150):
        azimuth = rng.uniform(0.0, 2.0 * math.pi)
        # A low cylindrical field stays in the orbiting camera's upper field of
        # view. Its large radius keeps it visually behind the bounded set.
        radius = rng.uniform(32.0, 46.0)
        center = (radius * math.cos(azimuth), radius * math.sin(azimuth), rng.uniform(-12.0, -0.5))
        size = rng.uniform(0.035, 0.085) * (1.65 if index % 19 == 0 else 1.0)
        offset = len(vertices)
        vertices.extend(((center[0] + size, center[1], center[2]), (center[0] - size, center[1], center[2]),
                         (center[0], center[1] + size, center[2]), (center[0], center[1] - size, center[2]),
                         (center[0], center[1], center[2] + size), (center[0], center[1], center[2] - size)))
        faces.extend(((offset, offset + 2, offset + 4), (offset + 2, offset + 1, offset + 4),
                      (offset + 1, offset + 3, offset + 4), (offset + 3, offset, offset + 4),
                      (offset + 2, offset, offset + 5), (offset + 1, offset + 2, offset + 5),
                      (offset + 3, offset + 1, offset + 5), (offset, offset + 3, offset + 5)))
    mesh = bpy.data.meshes.new("a8_star_field_mesh")
    mesh.from_pydata(vertices, [], faces)
    stars = bpy.data.objects.new("a8_star_field", mesh)
    mesh.materials.append(emission_material("a8_starlight", (0.48, 0.66, 1.0), 10.0))
    scene.collection.objects.link(stars)


def build_orbital_campfire_composition(scene, camera, seed):
    import math

    build_star_field(scene, seed)
    moon_material = emission_material("a8_moon_surface", (0.42, 0.49, 0.64), 0.55)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, location=(4.0, 8.0, 2.5), scale=(0.82, 0.82, 0.82))
    moon = bpy.context.object
    moon.name = "a8_moon"
    moon.data.materials.append(moon_material)
    noise = moon_material.node_tree.nodes.new(type="ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 5.5
    noise.inputs["Detail"].default_value = 5.0
    bump = moon_material.node_tree.nodes.new(type="ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.32
    bump.inputs["Distance"].default_value = 0.18
    moon_material.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    moon_material.node_tree.links.new(bump.outputs["Normal"], moon_material.node_tree.nodes["Principled BSDF"].inputs["Normal"])

    flame_layers = (
        ((-0.08, 0.03, 0.20), (1.0, 0.86, 1.0), (1.0, 0.025, 0.002), 1.5),
        ((0.09, -0.04, 0.23), (0.72, 0.62, 0.82), (1.0, 0.16, 0.004), 2.0),
        ((0.0, 0.04, 0.27), (0.42, 0.38, 0.64), (1.0, 0.46, 0.015), 2.6),
    )
    for index, (location, scale, color, strength) in enumerate(flame_layers):
        segments = 14
        ring_spec = ((0.0, 0.10, 0.0), (0.24, 0.28, 0.02), (0.55, 0.22, -0.025), (0.82, 0.13, 0.035), (1.12, 0.0, 0.0))
        vertices = []
        for z_value, radius, x_offset in ring_spec:
            if radius == 0.0:
                vertices.append((x_offset, 0.0, z_value))
            else:
                vertices.extend(
                    (x_offset + radius * math.cos(2.0 * math.pi * step / segments),
                     radius * math.sin(2.0 * math.pi * step / segments), z_value)
                    for step in range(segments)
                )
        faces = []
        first_ring = 1
        for step in range(segments):
            faces.append((0, first_ring + step, first_ring + ((step + 1) % segments)))
        second_ring = first_ring + segments
        third_ring = second_ring + segments
        for lower, upper in ((first_ring, second_ring), (second_ring, third_ring)):
            for step in range(segments):
                faces.append((lower + step, upper + step, upper + ((step + 1) % segments), lower + ((step + 1) % segments)))
        apex = len(vertices) - 1
        for step in range(segments):
            faces.append((third_ring + step, apex, third_ring + ((step + 1) % segments)))
        mesh = bpy.data.meshes.new(f"a8_flame_{index + 1}_mesh")
        mesh.from_pydata(vertices, [], faces)
        flame = bpy.data.objects.new(f"a8_flame_{index + 1}", mesh)
        scene.collection.objects.link(flame)
        flame.location = location
        flame.name = f"a8_flame_{index + 1}"
        flame.scale = scale
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        flame.data.materials.append(emission_material(f"a8_flame_{index + 1}_material", color, strength))
        for frame, factor in ((scene.frame_start, 1.0), ((scene.frame_start + scene.frame_end) // 2, 1.08), (scene.frame_end, 1.0)):
            flame.scale.z = scale[2] * factor
            flame.keyframe_insert(data_path="scale", frame=frame)

    orbit = bpy.data.objects.new("a8_camera_orbit", None)
    orbit.location = (0.0, 0.0, 1.15)
    scene.collection.objects.link(orbit)
    camera.parent = orbit
    target = bpy.data.objects.new("a8_camera_target", None)
    target.location = (0.0, 0.0, 1.0)
    scene.collection.objects.link(target)
    track = camera.constraints.new(type="TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    for frame, angle in ((scene.frame_start, 0.0), (scene.frame_end, 2.0 * math.pi)):
        orbit.rotation_euler[2] = angle
        orbit.keyframe_insert(data_path="rotation_euler", index=2, frame=frame)
    set_action_interpolation(orbit, "LINEAR")


def build_composition(spec, scene, camera, seed):
    preset = spec["preset"]
    if preset == "none":
        return
    if preset == "orbital_campfire_study":
        build_orbital_campfire_composition(scene, camera, seed)
        return
    raise ValueError(f"unsupported composition preset: {preset}")


def apply_surface_look(materials, profile):
    for material in sorted(materials.values(), key=lambda entry: entry.name):
        node_tree = material.node_tree
        principled = node_tree.nodes.get("Principled BSDF")
        if principled is None:
            continue

        remove_nodes_with_prefix(node_tree.nodes, "SOUL_SURFACE_")

        if profile == "clean":
            set_input_value(principled, "Roughness", 0.36)
            set_input_value(principled, "Metallic", 0.02)
            set_input_value(principled, "Sheen", 0.0)
            set_input_value(principled, "Clearcoat", 0.0)
            set_input_value(principled, "Subsurface", 0.0)
        elif profile == "organic":
            noise = node_tree.nodes.new(type="ShaderNodeTexNoise")
            noise.name = "SOUL_SURFACE_NOISE"
            noise.inputs["Scale"].default_value = 12.0
            noise.inputs["Detail"].default_value = 2.0
            noise.inputs["Roughness"].default_value = 0.5
            bump = node_tree.nodes.new(type="ShaderNodeBump")
            bump.name = "SOUL_SURFACE_BUMP"
            bump.inputs["Strength"].default_value = 0.40
            bump.inputs["Distance"].default_value = 0.15
            safe_link(node_tree, get_node_output(noise, "Fac"), get_node_input(bump, "Height"))
            safe_link(node_tree, get_node_output(bump, "Normal"), get_node_input(principled, "Normal"))
            set_input_value(principled, "Sheen", 0.12)
            set_input_value(principled, "Roughness", 0.68)
            set_input_value(principled, "Clearcoat", 0.08)
        elif profile == "crystalline":
            musgrave = node_tree.nodes.new(type="ShaderNodeTexNoise")
            musgrave.name = "SOUL_SURFACE_CRYSTAL_NOISE"
            musgrave.inputs["Scale"].default_value = 40.0
            musgrave.inputs["Detail"].default_value = 2.0
            bump = node_tree.nodes.new(type="ShaderNodeBump")
            bump.name = "SOUL_SURFACE_CRYSTAL_BUMP"
            bump.inputs["Strength"].default_value = 0.22
            bump.inputs["Distance"].default_value = 0.4
            safe_link(node_tree, get_node_output(musgrave, "Fac"), get_node_input(bump, "Height"))
            safe_link(node_tree, get_node_output(bump, "Normal"), get_node_input(principled, "Normal"))
            fresnel = node_tree.nodes.new(type="ShaderNodeFresnel")
            fresnel.name = "SOUL_SURFACE_FRESNEL"
            fresnel.inputs["IOR"].default_value = 1.46
            safe_link(node_tree, get_node_output(fresnel, "Fac"), get_node_input(principled, "Specular IOR Level", "Specular Tint", "Specular"))
            set_input_value(principled, "Specular", 0.8)
            set_input_value(principled, "Roughness", 0.2)
            set_input_value(principled, "Transmission", 0.02)
            set_input_value(principled, "Clearcoat", 0.05)
            set_input_value(principled, "Clearcoat Roughness", 0.06)
            set_input_value(principled, "Metallic", 0.15)
        elif profile == "machined":
            set_input_value(principled, "Roughness", 0.25)
            set_input_value(principled, "Metallic", 0.36)
            set_input_value(principled, "Clearcoat", 0.40)
            set_input_value(principled, "Clearcoat Roughness", 0.08)
            set_input_value(principled, "Anisotropic", 0.18)
            set_input_value(principled, "Sheen", 0.02)


def apply_atmosphere(world, profile):
    world.mist_settings.use_mist = profile in {"mist", "void_haze"}
    world.mist_settings.intensity = 0.025
    world.mist_settings.depth = 18.0
    world.mist_settings.start = 0.0
    world.mist_settings.falloff = "QUADRATIC"

    if profile == "none":
        return

    node_tree = world.node_tree
    output_node = next((node for node in node_tree.nodes if node.bl_idname == "ShaderNodeOutputWorld"), None)
    background = next((node for node in node_tree.nodes if node.bl_idname == "ShaderNodeBackground"), None)
    if output_node is None or background is None:
        return

    existing = next((node for node in node_tree.nodes if node.name == "SOUL_WORLD_VOLUME"), None)
    if existing:
        node_tree.nodes.remove(existing)

    volume = node_tree.nodes.new(type="ShaderNodeVolumeScatter")
    volume.name = "SOUL_WORLD_VOLUME"
    volume.inputs["Density"].default_value = 0.008 if profile == "void_haze" else 0.003
    volume.location = (background.location[0], background.location[1] - 260)
    if profile == "void_haze":
        volume.inputs["Color"].default_value = (0.08, 0.03, 0.16, 1.0)
    else:
        volume.inputs["Color"].default_value = (0.10, 0.04, 0.20, 1.0)
    node_tree.links.new(volume.outputs["Volume"], output_node.inputs["Volume"])


def apply_camera_look(camera_data, profile):
    camera_data.dof.use_dof = profile != "crisp"
    if profile == "crisp":
        camera_data.dof.aperture_fstop = 64.0
        camera_data.dof.focus_distance = 0.0
        return
    if profile == "subtle_dof":
        camera_data.dof.aperture_fstop = 4.0
        camera_data.dof.focus_distance = 8.0
        if hasattr(camera_data.dof, "blades"):
            camera_data.dof.blades = 6
    else:
        camera_data.dof.aperture_fstop = 2.8
        camera_data.dof.focus_distance = 8.2
        if hasattr(camera_data.dof, "blades"):
            camera_data.dof.blades = 8
    camera_data.dof.focus_object = None


def apply_glow(scene, profile):
    if profile == "none":
        return

    if not scene.use_nodes:
        scene.use_nodes = True
    node_tree = getattr(scene, "node_tree", None) or getattr(scene, "compositing_node_group", None)
    if node_tree is None:
        node_tree = bpy.data.node_groups.new(name="SoulCompositor", type="CompositorNodeTree")
        scene.compositing_node_group = node_tree
    nodes = node_tree.nodes
    links = node_tree.links

    for node in list(nodes):
        if node.name.startswith("SOUL_GLOW"):
            nodes.remove(node)

    render_layer = next((node for node in nodes if node.bl_idname in ("CompositorNodeRLayers", "CompositorNodeRenderLayers")), None)
    if render_layer is None:
        render_layer = nodes.new(type="CompositorNodeRLayers")
        render_layer.name = "Render Layers"
        render_layer.location = (-260, 220)

    composite = next((node for node in nodes if node.bl_idname == "NodeGroupOutput"), None)
    if composite is None:
        port_kind = "SO" + "CKET"
        if not any(item.item_type == port_kind and item.in_out == "OUTPUT" and item.name == "Image" for item in node_tree.interface.items_tree):
            add_port = getattr(node_tree.interface, "new_" + port_kind.lower())
            type_key = port_kind.lower() + "_type"
            add_port(name="Image", in_out="OUTPUT", **{type_key: "Node" + port_kind.title() + "Color"})
        composite = nodes.new(type="NodeGroupOutput")
        composite.name = "Soul Composite Output"
        composite.location = (360, 220)

    glare = nodes.new(type="CompositorNodeGlare")
    glare.name = "SOUL_GLOW_GLARE"
    glare.location = (80, 220)
    get_node_input(glare, "Type").default_value = "Bloom"
    get_node_input(glare, "Quality").default_value = "High"
    get_node_input(glare, "Threshold").default_value = 0.70 if profile == "soft" else 0.58
    get_node_input(glare, "Strength").default_value = 0.55 if profile == "soft" else 0.82
    get_node_input(glare, "Saturation").default_value = 1.08 if profile == "soft" else 1.22
    get_node_input(glare, "Size").default_value = 0.42 if profile == "soft" else 0.58
    get_node_input(glare, "Tint").default_value = (0.78, 0.88, 1.0, 1.0) if profile == "soft" else (0.48, 0.18, 1.0, 1.0)

    links.new(render_layer.outputs["Image"], glare.inputs["Image"])

    links.new(glare.outputs["Image"], composite.inputs["Image"])


def apply_grade(scene, profile):
    desired = {
        "neutral": ("Standard", "None"),
        "cinematic": ("AgX", "High Contrast"),
        "high_contrast": ("AgX", "Very High Contrast"),
    }.get(profile, ("Standard", "None"))

    try:
        view_transform, look = desired
        scene.view_settings.view_transform = view_transform
        if hasattr(scene.view_settings, "look"):
            scene.view_settings.look = look
    except Exception:
        # Fallback for older/stricter Blender versions.
        scene.view_settings.view_transform = "Standard"
        if hasattr(scene.view_settings, "look"):
            scene.view_settings.look = "None"


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
                interpolation_owner = target.node_tree if target else None
            elif section == "world":
                target = bpy.context.scene.world
                interpolation_owner = target.node_tree if target else None
            elif section == "camera":
                target = bpy.data.objects.get(camera_id)
                interpolation_owner = target.data if target else None
            elif section == "lights":
                target = bpy.data.objects.get(entry["target_id"])
                interpolation_owner = target.data if target else None
            else:
                target = bpy.data.objects.get(entry["target_id"])
                interpolation_owner = target

            if target is None:
                raise ValueError(f"animation target is unavailable: {entry['target_id']}")

            for frame, value in zip(entry["frames"], entry["values"]):
                if section == "materials":
                    principled = target.node_tree.nodes.get("Principled BSDF")
                    if entry["property"] == "emission_strength":
                        principled.inputs["Emission Strength"].default_value = float(value)
                        principled.inputs["Emission Strength"].keyframe_insert(data_path="default_value", frame=frame)
                    elif entry["property"] == "metallic":
                        principled.inputs["Metallic"].default_value = float(value)
                        principled.inputs["Metallic"].keyframe_insert(data_path="default_value", frame=frame)
                    elif entry["property"] == "roughness":
                        principled.inputs["Roughness"].default_value = float(value)
                        principled.inputs["Roughness"].keyframe_insert(data_path="default_value", frame=frame)
                    else:
                        raise ValueError("unsupported material animation property")
                    continue

                if section == "world":
                    target.horizon_color = value
                    background = target.node_tree.nodes.get("Background")
                    background.inputs["Color"].default_value = tuple(value) + (1.0,)
                    background.inputs["Color"].keyframe_insert(data_path="default_value", frame=frame)
                    continue

                if section == "camera" and entry["property"] == "lens":
                    target.data.lens = float(value)
                    target.data.keyframe_insert(data_path="lens", frame=frame)
                    continue

                if section == "lights" and entry["property"] == "energy":
                    target.data.energy = float(value)
                    target.data.keyframe_insert(data_path="energy", frame=frame)
                    continue

                if section in {"objects", "lights", "camera"}:
                    setattr(target, entry["property"], value)
                    target.keyframe_insert(data_path=entry["property"], frame=frame)

            if interpolation_owner is not None:
                set_action_interpolation(interpolation_owner, entry["interpolation"])


def clear_scene():
    for item in list(bpy.data.objects):
        bpy.data.objects.remove(item, do_unlink=True)
    for item in list(bpy.data.materials):
        bpy.data.materials.remove(item, do_unlink=True)
    for item in list(bpy.data.lights):
        bpy.data.lights.remove(item, do_unlink=True)


def run(manifest, blend_path, still_path, still_frame, asset_map):
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

    apply_grade(scene, manifest["look"]["grade"])

    # Camera
    camera_data = bpy.data.cameras.new(manifest["camera"]["id"])
    camera_data.lens = manifest["camera"]["lens"]
    camera = bpy.data.objects.new(manifest["camera"]["id"], camera_data)
    camera.location = manifest["camera"]["location"]
    camera.rotation_euler = manifest["camera"]["rotation_euler"]
    bpy.context.scene.collection.objects.link(camera)
    scene.camera = camera
    apply_camera_look(camera_data, manifest["look"]["camera"])

    materials = build_material_collection(manifest["materials"])
    build_lights(manifest["lights"], bpy.context.scene.collection)
    build_objects(manifest["objects"], materials)
    build_organics(manifest["organics"], materials, scene)
    build_curated_assets(manifest["curated_assets"], asset_map, scene.collection)
    build_composition(manifest["composition"], scene, camera, manifest["render"]["seed"])

    apply_surface_look(materials, manifest["look"]["surface"])
    apply_atmosphere(world, manifest["look"]["atmosphere"])
    apply_glow(scene, manifest["look"]["glow"])
    apply_animation(manifest)

    if manifest["curated_assets"]:
        bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, check_existing=False)
    scene.frame_set(still_frame)
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

    require_file_name(manifest["output"]["blend_name"], "output.blend_name")
    require_file_name(manifest["output"]["still_name"], "output.still_name")

    blend_path = os.path.abspath(args.blend_path)
    still_path = os.path.abspath(args.still_path)
    manifest["output"]["blend_name"] = os.path.basename(blend_path)
    manifest["output"]["still_name"] = os.path.basename(still_path)

    global bpy
    import bpy  # local import keeps py_compile lightweight and allows structural checks.

    required_assets = {entry["asset_id"] for entry in manifest["curated_assets"]}
    asset_map = load_curated_asset_map(args.asset_root, args.asset_registry, required_assets)
    clear_scene()
    run(manifest, blend_path, still_path, int(manifest["output"]["still_frame"]), asset_map)
    frame_count = manifest["render"]["frame_end"] - manifest["render"]["frame_start"] + 1
    print("SOUL_SCENE_ADAPTER_RUN=" + json.dumps({"blend_path": blend_path, "still_path": still_path, "frames": frame_count, "objects": len(manifest["objects"]), "organics": len(manifest["organics"]), "curated_assets": len(manifest["curated_assets"]), "composition": manifest["composition"]["preset"]}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
