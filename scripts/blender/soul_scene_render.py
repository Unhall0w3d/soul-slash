#!/usr/bin/env python3
"""Render one bounded frame interval from a trusted Soul-authored blend file."""

import argparse
import json
import os
import sys

import bpy


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames-dir", required=True)
    parser.add_argument("--frame-start", required=True, type=int)
    parser.add_argument("--frame-end", required=True, type=int)
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    return parser.parse_args(values)


def main():
    args = arguments()
    scene = bpy.context.scene
    if not (scene.frame_start <= args.frame_start <= args.frame_end <= scene.frame_end):
        raise ValueError("requested frame interval is outside the trusted scene")
    directory = os.path.abspath(args.frames_dir)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = os.path.join(directory, "frame_")
    original_start, original_end = scene.frame_start, scene.frame_end
    scene.frame_start, scene.frame_end = args.frame_start, args.frame_end
    bpy.ops.render.render(animation=True)
    scene.frame_start, scene.frame_end = original_start, original_end
    print("SOUL_SCENE_RENDER=" + json.dumps({"frame_start": args.frame_start, "frame_end": args.frame_end}))


if __name__ == "__main__":
    main()
