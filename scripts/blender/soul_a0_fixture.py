"""Repository-owned Blender A0 scene builder.

The fixture uses Blender data blocks and fixed values only. It accepts one
contained output .blend path after ``--`` and does not load external assets,
extensions, add-ons, or model-authored Python.
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend-path", required=True)
    parser.add_argument("--width", required=True, type=int)
    parser.add_argument("--height", required=True, type=int)
    parser.add_argument("--fps", required=True, type=int)
    parser.add_argument("--frames", required=True, type=int)
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(values)


def material(name, color, metallic, roughness, emission=None, strength=0.0):
    item = bpy.data.materials.new(name)
    item.diffuse_color = (*color, 1.0)
    item.use_nodes = True
    shader = item.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if emission is not None:
        emission_input = shader.inputs.get("Emission Color") or shader.inputs.get("Emission")
        strength_input = shader.inputs.get("Emission Strength")
        if emission_input is not None:
            emission_input.default_value = (*emission, 1.0)
        if strength_input is not None:
            strength_input.default_value = strength
    return item


def mesh_object(name, vertices, faces, material_value):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    item = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(item)
    item.data.materials.append(material_value)
    return item


def ring(name, radius, z, material_value, tilt):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = 0.035
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    points = 64
    spline.points.add(points - 1)
    for index in range(points):
        angle = (2.0 * math.pi * index) / points
        spline.points[index].co = (radius * math.cos(angle), radius * math.sin(angle), 0.0, 1.0)
    spline.use_cyclic_u = True
    item = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(item)
    item.location.z = z
    item.rotation_euler = tilt
    item.data.materials.append(material_value)
    return item


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


args = arguments()
blend_path = os.path.abspath(args.blend_path)
if os.path.islink(blend_path) or not os.path.isdir(os.path.dirname(blend_path)):
    raise RuntimeError("blend destination must have an existing non-symlink parent")

for item in list(bpy.data.objects):
    bpy.data.objects.remove(item, do_unlink=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = args.width
scene.render.resolution_y = args.height
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.fps = args.fps
scene.frame_start = 1
scene.frame_end = args.frames
scene.world.color = (0.002, 0.006, 0.012)

copper = material("SoulCopper", (0.42, 0.12, 0.045), 0.78, 0.22)
cyan = material("SoulCyan", (0.0, 0.42, 0.62), 0.22, 0.14, (0.0, 0.78, 1.0), 4.0)
slate = material("AbyssalSlate", (0.008, 0.016, 0.028), 0.18, 0.48)

floor = mesh_object(
    "Slate",
    [(-8, -8, 0), (8, -8, 0), (8, 8, 0), (-8, 8, 0)],
    [(0, 1, 2, 3)],
    slate,
)
floor.location.z = -1.55

for index, x in enumerate((-3.2, 3.2)):
    pillar = mesh_object(
        "Pillar%02d" % index,
        [
            (-0.22, -0.22, -1.5), (0.22, -0.22, -1.5), (0.22, 0.22, -1.5), (-0.22, 0.22, -1.5),
            (-0.22, -0.22, 2.4), (0.22, -0.22, 2.4), (0.22, 0.22, 2.4), (-0.22, 0.22, 2.4),
        ],
        [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7)],
        copper,
    )
    pillar.location.x = x
    pillar.location.y = 0.55

rings = [
    ring("OrbitA", 1.25, 0.0, cyan, (math.radians(67), 0.0, math.radians(8))),
    ring("OrbitB", 1.65, 0.0, copper, (math.radians(82), math.radians(25), 0.0)),
    ring("OrbitC", 2.05, 0.0, cyan, (math.radians(56), math.radians(-18), math.radians(21))),
]
for index, item in enumerate(rings):
    # A rotationally symmetric ring can animate correctly while appearing
    # static. Attach a small phase marker so the technical preview makes
    # temporal motion visibly reviewable without relying on pixel hashes.
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.11)
    marker = bpy.context.object
    marker.name = "OrbitMarker%02d" % index
    marker.data.materials.append(copper if index % 2 == 0 else cyan)
    marker_radius = 1.25 + (index * 0.4)
    direction = 1 if index % 2 == 0 else -1
    for phase, frame in enumerate((1, 7, 13, 19, args.frames + 1)):
        angle = direction * ((math.tau * phase) / 4.0) + (index * 0.55)
        marker.location = (
            marker_radius * math.cos(angle),
            -0.08 - (index * 0.035),
            marker_radius * math.sin(angle),
        )
        marker.keyframe_insert(data_path="location", frame=frame)
    item.rotation_euler.rotate_axis("Z", index * 0.3)
    item.keyframe_insert(data_path="rotation_euler", frame=1)
    item.rotation_euler.rotate_axis("Z", math.tau * (1 if index % 2 == 0 else -1))
    item.keyframe_insert(data_path="rotation_euler", frame=args.frames + 1)

light_data = bpy.data.lights.new("SoulKey", "AREA")
light_data.energy = 1150
light_data.color = (0.12, 0.72, 1.0)
light_data.shape = "DISK"
light_data.size = 5.0
light = bpy.data.objects.new("SoulKey", light_data)
bpy.context.scene.collection.objects.link(light)
light.location = (0.0, -2.0, 5.0)

camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
bpy.context.scene.collection.objects.link(camera)
scene.camera = camera
camera.location = (0.0, -10.5, 2.2)
camera.data.lens = 48
point_camera(camera, (0.0, 0.0, 0.0))

scene["soul_fixture_schema"] = "soul.blender.fixture.a0.v1"
scene["soul_fixture_seed"] = 5200
bpy.ops.wm.save_as_mainfile(filepath=blend_path, check_existing=False)
print(
    "SOUL_BLENDER_FIXTURE="
    + json.dumps(
        {
            "blend_path": blend_path,
            "engine": scene.render.engine,
            "width": args.width,
            "height": args.height,
            "fps": args.fps,
            "frames": args.frames,
        },
        sort_keys=True,
    )
)
