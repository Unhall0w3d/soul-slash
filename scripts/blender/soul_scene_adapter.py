#!/usr/bin/env python3
"""Bounded Blender scene adapter for Soul scene manifests.

This script validates a closed manifest, applies a bounded look profile
(surface / atmosphere / camera / glow / grade), and renders/exports the
blend and still image deterministically.
"""

from __future__ import annotations

import argparse
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
    }
    if set(manifest.keys()) == (top_level | {"look"}):
        pass
    elif set(manifest.keys()) == top_level - {"look"}:
        manifest["look"] = {}
    else:
        reject_unknown(manifest, top_level, "manifest")

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

    for key in ("id", "project_id", "revision", "music_candidate_id"):
        require_string(identity[key], f"identity.{key}", min_length=1, max_length=64)

    require_string(manifest["schema_version"], "schema_version", 1, 64)

    # Look migration + strict map validation (A1 manifests are compatible via defaults).
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

    apply_surface_look(materials, manifest["look"]["surface"])
    apply_atmosphere(world, manifest["look"]["atmosphere"])
    apply_glow(scene, manifest["look"]["glow"])
    apply_animation(manifest)

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

    clear_scene()
    run(manifest, blend_path, still_path, int(manifest["output"]["still_frame"]))
    frame_count = manifest["render"]["frame_end"] - manifest["render"]["frame_start"] + 1
    print("SOUL_SCENE_ADAPTER_RUN=" + json.dumps({"blend_path": blend_path, "still_path": still_path, "frames": frame_count, "objects": len(manifest["objects"]) }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
