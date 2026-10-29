#!/bin/sh
# Blender's current repository build needs libcudart.so.13. Keep this library
# private to Blender; the GTX 1070 model toolchain remains on CUDA 12.9.
exec env LD_LIBRARY_PATH="/home/bhones/.local/share/soul/blender-runtime/cuda-13.4.49/nvidia/cu13/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" /usr/bin/blender "$@"
