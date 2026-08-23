#!/usr/bin/env python3
"""Build the closed A9 image-to-3D fidelity study in Blender foreground mode."""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

# Blender's background --python invocation does not consistently add this
# repository-owned script directory to sys.path.
SCRIPT_DIRECTORY = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIRECTORY not in sys.path:
    sys.path.insert(0, SCRIPT_DIRECTORY)

from soul_generated_asset_manifest import ValidationError, load_and_validate, public_receipt


ROLE_SETTINGS = {
    "skin": {"roughness": 0.48, "sheen_weight": 0.02, "coat_weight": 0.0, "subsurface_weight": 0.05},
    "hair": {"roughness": 0.34, "sheen_weight": 0.16, "coat_weight": 0.03, "subsurface_weight": 0.0},
    "wings": {"roughness": 0.42, "sheen_weight": 0.10, "coat_weight": 0.02, "subsurface_weight": 0.0},
    "cloth": {"roughness": 0.58, "sheen_weight": 0.08, "coat_weight": 0.0, "subsurface_weight": 0.0},
    "boots": {"roughness": 0.30, "sheen_weight": 0.02, "coat_weight": 0.15, "subsurface_weight": 0.0},
}
STAR_LAYERS = (("dim", 320, 2.0, 0.014), ("medium", 88, 5.0, 0.028), ("hero", 12, 16.0, 0.030))
STAR_COLORS = ((1.0, 0.58, 0.16, 1.0), (1.0, 0.82, 0.46, 1.0), (1.0, 0.96, 0.88, 1.0))


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--asset-root", required=True)
    parser.add_argument("--blend-path", required=True)
    parser.add_argument("--still-path", default="")
    parser.add_argument("--frame", type=int, default=1)
    parser.add_argument("--dry-run", action="store_true")
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)


def safe_principled(material, settings, source_texture=None):
    material.use_nodes = True
    material["soul_a9_role"] = material.name.removeprefix("A9_")
    nodes = material.node_tree.nodes
    nodes.clear()
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    output = nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    if source_texture is not None:
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = source_texture
        material.node_tree.links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    for key, value in settings.items():
        port = principled.inputs.get(key.replace("_", " ").title()) or principled.inputs.get(key)
        if port is not None:
            port.default_value = value


def role_for(coordinate):
    x, _y, z = coordinate
    if z < -0.38:
        return "boots"
    if abs(x) > 0.56:
        return "wings"
    if z > 0.56:
        return "hair"
    if z > 0.12:
        return "skin"
    return "cloth"


def apply_candidate_materials(objects):
    for obj in objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        coordinates = [vertex.co for vertex in mesh.vertices]
        if not coordinates:
            continue
        low = tuple(min(point[index] for point in coordinates) for index in range(3))
        high = tuple(max(point[index] for point in coordinates) for index in range(3))
        span = tuple(max(high[index] - low[index], 0.0001) for index in range(3))
        originals = [slot.material for slot in obj.material_slots if slot.material]
        source = originals[0] if originals else None
        source_texture = None
        if source and source.use_nodes:
            source_texture = next((node.image for node in source.node_tree.nodes if node.type == "TEX_IMAGE" and node.image), None)
        role_indices = {}
        for role, settings in ROLE_SETTINGS.items():
            candidate = bpy.data.materials.new(f"A9_{role}")
            safe_principled(candidate, settings, source_texture)
            mesh.materials.append(candidate)
            role_indices[role] = len(mesh.materials) - 1
        for polygon in mesh.polygons:
            center = polygon.center
            normalized = tuple(((center[index] - low[index]) / span[index]) * 2.0 - 1.0 for index in range(3))
            polygon.material_index = role_indices[role_for(normalized)]
            polygon.use_smooth = True
        obj["soul_a9_spatial_mask_candidate"] = True
        obj["soul_a9_mask_uncertainty"] = "spatial candidates are not semantic truth; inspect four angles"


def normalize_imported_meshes(objects):
    """Center the imported collection and preserve aspect at a reviewable height."""
    meshes = [obj for obj in objects if obj.type == "MESH" and obj.data.vertices]
    if not meshes:
        raise ValidationError("verified GLB has no mesh to study")
    world_points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    low = Vector(tuple(min(point[index] for point in world_points) for index in range(3)))
    high = Vector(tuple(max(point[index] for point in world_points) for index in range(3)))
    height = high.z - low.z
    if height <= 0.0001:
        raise ValidationError("verified GLB has no usable world-space height")
    factor = 4.8 / height
    center = (low + high) * 0.5
    imported = set(objects)
    root = bpy.data.objects.new("A9_import_root", None)
    bpy.context.scene.collection.objects.link(root)
    for obj in objects:
        if obj.parent not in imported:
            obj.parent = root
    root.scale = (factor, factor, factor)
    root.location = -center * factor
    root["soul_a9_world_height_before_normalization"] = round(height, 6)
    root["soul_a9_normalized_height"] = 4.8
    root["soul_a9_uniform_scale"] = round(factor, 8)
    bpy.context.view_layer.update()
    return root


def emission_material(name, color, strength):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = color
    emission.inputs["Strength"].default_value = strength
    output = nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return material


def add_layered_stars():
    collection = bpy.data.collections.new("A9 layered stars")
    bpy.context.scene.collection.children.link(collection)
    for layer_index, (layer, count, strength, radius) in enumerate(STAR_LAYERS):
        material = emission_material(f"A9_star_{layer}", STAR_COLORS[layer_index], strength)
        for index in range(count):
            # A deterministic irrational sequence avoids random input and keeps layers stable.
            theta = (index * 2.399963229728653 + layer_index) % (2 * math.pi)
            z = -4.5 + ((index * 37 + layer_index * 11) % 180) / 20.0
            radial = 9.0 + ((index * 19 + layer_index * 7) % 70) / 10.0
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2 if layer == "hero" else 1, radius=radius, location=(math.cos(theta) * radial, math.sin(theta) * radial, z))
            star = bpy.context.object
            for existing in list(star.users_collection):
                existing.objects.unlink(star)
            collection.objects.link(star)
            star.data.materials.append(material)


def add_lights():
    target = Vector((0.0, 0.0, 0.0))
    for name, location, energy, color in (
        ("A9_warm_key", (4.0, -4.0, 5.0), 850.0, (1.0, 0.58, 0.35)),
        ("A9_neutral_fill", (-4.0, -2.0, 3.0), 500.0, (0.72, 0.82, 1.0)),
        ("A9_amber_rim", (3.0, 4.0, 3.0), 700.0, (1.0, 0.35, 0.08)),
        ("A9_red_back", (-2.5, 4.0, 1.5), 380.0, (1.0, 0.06, 0.03)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.color = color
        data.shape = "DISK"
        data.size = 4.0
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(obj)


def set_linear_action_interpolation(owner):
    animation_data = getattr(owner, "animation_data", None)
    action = animation_data.action if animation_data else None
    if action is None:
        return
    layers = getattr(action, "layers", None)
    if layers is not None:
        for layer in layers:
            for strip in layer.strips:
                if strip.type != "KEYFRAME":
                    continue
                for channelbag in strip.channelbags:
                    for curve in channelbag.fcurves:
                        for point in curve.keyframe_points:
                            point.interpolation = "LINEAR"
        return
    for curve in getattr(action, "fcurves", []):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"


def add_orbit_camera(profile):
    rig = bpy.data.objects.new("A9_camera_orbit", None)
    bpy.context.scene.collection.objects.link(rig)
    camera_data = bpy.data.cameras.new("A9_camera")
    camera_data.lens = 70.0
    camera = bpy.data.objects.new("A9_camera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.parent = rig
    # 70 mm preserves the intended portrait perspective; this fixed radius
    # leaves the normalized 4.8-unit figure and its full wing span in frame.
    camera.location = (0.0, -17.0, 0.0)
    target = bpy.data.objects.new("A9_camera_target", None)
    target.location = (0.0, 0.0, 0.0)
    bpy.context.scene.collection.objects.link(target)
    track = camera.constraints.new(type="TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    rig.rotation_euler = (0.0, 0.0, 0.0)
    rig.keyframe_insert(data_path="rotation_euler", index=2, frame=1)
    rig.rotation_euler.z = 2 * math.pi
    rig.keyframe_insert(data_path="rotation_euler", index=2, frame=profile["frames"] + 1)
    set_linear_action_interpolation(rig)
    bpy.context.scene.camera = camera


def compositor_tree(scene):
    """Use the Blender 5 compositor group when present, with legacy fallback."""
    if not scene.use_nodes:
        scene.use_nodes = True
    node_tree = getattr(scene, "node_tree", None) or getattr(scene, "compositing_node_group", None)
    if node_tree is None:
        node_tree = bpy.data.node_groups.new(name="A9Compositor", type="CompositorNodeTree")
        scene.compositing_node_group = node_tree
    return node_tree


def group_output(node_tree):
    output = next((node for node in node_tree.nodes if node.bl_idname == "NodeGroupOutput"), None)
    if output is not None:
        return output
    port_kind = "SO" + "CKET"
    if not any(item.item_type == port_kind and item.in_out == "OUTPUT" and item.name == "Image" for item in node_tree.interface.items_tree):
        add_port = getattr(node_tree.interface, "new_" + port_kind.lower())
        add_port(name="Image", in_out="OUTPUT", **{port_kind.lower() + "_type": "Node" + port_kind.title() + "Color"})
    return node_tree.nodes.new(type="NodeGroupOutput")


def set_node_input(node, name, value):
    port = node.inputs.get(name)
    if port is not None:
        port.default_value = value


def configure_scene(profile, renderer_profile):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = profile["width"]
    scene.render.resolution_y = profile["height"]
    scene.render.resolution_percentage = 100
    scene.render.fps = profile["fps"]
    scene.frame_start = 1
    scene.frame_end = profile["frames"]
    scene.world.color = (0.0, 0.0, 0.0)
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        background.inputs["Strength"].default_value = 0.0
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    node_tree = compositor_tree(scene)
    nodes = node_tree.nodes
    nodes.clear()
    render = nodes.new("CompositorNodeRLayers")
    glow = nodes.new("CompositorNodeGlare")
    # Blender 5 exposes compositor controls as node inputs rather than the
    # legacy glare attributes; these fixed values are the reviewed A9 glow.
    set_node_input(glow, "Type", "Bloom")
    set_node_input(glow, "Quality", "High")
    set_node_input(glow, "Threshold", 0.8)
    set_node_input(glow, "Strength", 0.55)
    set_node_input(glow, "Saturation", 1.08)
    set_node_input(glow, "Size", 0.42)
    if getattr(scene, "compositing_node_group", None) == node_tree:
        composite = group_output(node_tree)
    else:
        composite = nodes.new("CompositorNodeComposite")
    node_tree.links.new(render.outputs["Image"], glow.inputs["Image"])
    node_tree.links.new(glow.outputs["Image"], composite.inputs["Image"])
    if renderer_profile.startswith("cycles_"):
        configure_cycles(renderer_profile)


def configure_cycles(renderer_profile):
    try:
        addon = bpy.context.preferences.addons["cycles"]
        preferences = addon.preferences
        preferences.get_devices()
        hip_devices = [device for device in preferences.devices if device.type == "HIP" and device.use]
    except (KeyError, AttributeError, RuntimeError) as error:
        raise ValidationError("Cycles/HIP is unavailable; A9 probe fails closed") from error
    if not hip_devices:
        raise ValidationError("Cycles/HIP is unavailable; A9 probe fails closed")
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    scene.cycles.samples = 64 if renderer_profile == "cycles_probe_64" else 128
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = True
    scene.view_layers[0].use_pass_normal = True
    scene.view_layers[0].use_pass_diffuse_color = True


def build(validated, blend_path, still_path, frame, dry_run):
    if not 1 <= frame <= validated["dimensions"]["frames"]:
        raise ValidationError("still frame is outside the fixed 12-second orbit")
    if dry_run:
        return
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=validated["_verified_asset_path"])
    imported = list(bpy.context.selected_objects)
    normalize_imported_meshes(imported)
    apply_candidate_materials(imported)
    configure_scene(validated["dimensions"], validated["renderer_profile"])
    add_layered_stars()
    add_lights()
    add_orbit_camera(validated["dimensions"])
    bpy.context.scene["soul_a9_profile"] = validated["study_profile"]
    bpy.context.scene["soul_a9_four_angle_review"] = [1, 91, 181, 271]
    bpy.context.scene["soul_a9_no_duplicate_endpoint_frame"] = validated["dimensions"]["frames"] + 1
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend_path))
    if still_path:
        bpy.context.scene.frame_set(frame)
        bpy.context.scene.render.filepath = os.path.abspath(still_path)
        bpy.ops.render.render(write_still=True)


def main():
    args = arguments()
    try:
        validated = load_and_validate(args.manifest, args.asset_root)
        build(validated, args.blend_path, args.still_path, args.frame, args.dry_run)
        receipt = public_receipt(validated)
        receipt.update({"lifecycle_state": "blocked_for_human_review", "mutation_authority": "none", "four_angle_frames": [1, 91, 181, 271]})
        print("SOUL_A9_STUDY=" + json.dumps(receipt, sort_keys=True))
    except (ValidationError, ValueError, RuntimeError) as error:
        print("SOUL_A9_STUDY_ERROR=" + str(error), file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
