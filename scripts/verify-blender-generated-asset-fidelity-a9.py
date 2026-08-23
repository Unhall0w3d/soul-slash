#!/usr/bin/env python3
"""Deterministically verify the closed Blender generated-asset A9 boundary."""

from __future__ import annotations

import ast
import copy
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_MODULE = ROOT / "scripts/blender/soul_generated_asset_manifest.py"
STUDY_MODULE = ROOT / "scripts/blender/soul_generated_asset_study.py"
BRIEF = ROOT / "docs/soul/BLENDER_GENERATED_ASSET_FIDELITY_A9_BRIEF.md"
REVIEW = ROOT / "docs/assessments/BLENDER_GENERATED_ASSET_FIDELITY_A9_REVIEW.md"


class CheckFailure(RuntimeError):
    """Raised when one deterministic A9 assertion fails."""


def check(label: str, condition: bool, detail: str = "") -> None:
    if not condition:
        raise CheckFailure(f"{label}{': ' + detail if detail else ''}")
    print(f"PASS {label}")


def load_manifest_module():
    spec = importlib.util.spec_from_file_location("soul_a9_manifest", MANIFEST_MODULE)
    check("manifest validator module is importable", spec is not None and spec.loader is not None)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def fixture_manifest(module, asset: Path, **overrides) -> dict:
    digest = hashlib.sha256(asset.read_bytes()).hexdigest()
    value = {
        "schema_version": module.SCHEMA_VERSION,
        "asset": {
            "id": "fixture-winged-figure",
            "relative_path": asset.name,
            "bytes": asset.stat().st_size,
            "sha256": digest,
        },
        "study_profile": "baseline_720",
        "reconstruction_profile": "res_1024",
        "renderer_profile": "eevee_preview",
    }
    for key, replacement in overrides.items():
        if key.startswith("asset__"):
            value["asset"][key.removeprefix("asset__")] = replacement
        else:
            value[key] = replacement
    return value


def write_manifest(root: Path, value: dict, name: str = "study.json") -> Path:
    path = root / name
    path.write_text(json.dumps(value), encoding="utf-8")
    return path


def rejected(module, manifest: Path, root: Path, contains: str | None = None) -> bool:
    try:
        module.load_and_validate(str(manifest), str(root))
    except module.ValidationError as error:
        return contains is None or contains.lower() in str(error).lower()
    return False


def literal_assignment(tree: ast.Module, name: str):
    for node in tree.body:
        if isinstance(node, ast.Assign):
            if any(isinstance(target, ast.Name) and target.id == name for target in node.targets):
                return ast.literal_eval(node.value)
    raise CheckFailure(f"missing literal assignment {name}")


def cycles_function(tree: ast.Module) -> ast.FunctionDef:
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "configure_cycles":
            return node
    raise CheckFailure("missing configure_cycles function")


def run_cycles_contract(tree: ast.Module, validation_error: type[Exception]) -> None:
    node = copy.deepcopy(cycles_function(tree))
    module = ast.Module(body=[node], type_ignores=[])
    ast.fix_missing_locations(module)

    class Scene:
        def __init__(self):
            self.render = SimpleNamespace(engine="BLENDER_EEVEE")
            self.cycles = SimpleNamespace()
            self.view_layers = [SimpleNamespace()]

    def execute(addons, profile):
        scene = Scene()
        bpy = SimpleNamespace(
            context=SimpleNamespace(
                preferences=SimpleNamespace(addons=addons),
                scene=scene,
            )
        )
        scope = {"ValidationError": validation_error, "bpy": bpy}
        exec(compile(module, str(STUDY_MODULE), "exec"), scope)
        return scene, scope["configure_cycles"]

    scene, function = execute({}, "cycles_probe_64")
    try:
        function("cycles_probe_64")
    except validation_error as error:
        check("Cycles probe fails closed when the add-on is absent", "unavailable" in str(error).lower())
    else:
        raise CheckFailure("Cycles probe accepted a missing add-on")
    check("failed Cycles probe does not change the renderer", scene.render.engine == "BLENDER_EEVEE")

    no_hip = SimpleNamespace(preferences=SimpleNamespace(get_devices=lambda: None, devices=[]))
    scene, function = execute({"cycles": no_hip}, "cycles_probe_64")
    try:
        function("cycles_probe_64")
    except validation_error:
        pass
    else:
        raise CheckFailure("Cycles probe accepted an empty HIP inventory")
    check("Cycles probe rejects an empty HIP inventory", scene.render.engine == "BLENDER_EEVEE")

    hip = SimpleNamespace(type="HIP", use=True)
    with_hip = SimpleNamespace(preferences=SimpleNamespace(get_devices=lambda: None, devices=[hip]))
    scene, function = execute({"cycles": with_hip}, "cycles_probe_128")
    function("cycles_probe_128")
    check(
        "reviewed HIP evidence selects bounded Cycles settings",
        scene.render.engine == "CYCLES"
        and scene.cycles.device == "GPU"
        and scene.cycles.samples == 128
        and scene.cycles.use_adaptive_sampling is True
        and scene.cycles.use_denoising is True
        and scene.view_layers[0].use_pass_normal is True
        and scene.view_layers[0].use_pass_diffuse_color is True,
    )


def main() -> int:
    for path in (MANIFEST_MODULE, STUDY_MODULE, BRIEF, REVIEW):
        check(f"required A9 file exists: {path.relative_to(ROOT)}", path.is_file())

    module = load_manifest_module()
    result = subprocess.run(
        [sys.executable, str(MANIFEST_MODULE), "--self-test"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    check("validator self-test passes", result.returncode == 0 and "SOUL_A9_MANIFEST_SELF_TEST=ok" in result.stdout, result.stderr.strip())

    with tempfile.TemporaryDirectory(prefix="soul-a9-verify-") as directory:
        root = Path(directory) / "private"
        root.mkdir()
        asset = root / "fixture.glb"
        asset.write_bytes(b"glTF" + bytes(range(32)))
        valid = fixture_manifest(module, asset)
        manifest = write_manifest(root, valid)
        normalized = module.load_and_validate(str(manifest), str(root))
        receipt = module.public_receipt(normalized)
        check("valid manifest verifies exact byte count and digest", normalized["asset"] == {"id": valid["asset"]["id"], "bytes": len(asset.read_bytes()), "sha256": valid["asset"]["sha256"]})
        check("public receipt redacts private and relative paths", "_verified_asset_path" not in receipt and "relative_path" not in json.dumps(receipt) and str(root) not in json.dumps(receipt))

        outside = Path(directory) / "outside.json"
        outside.write_text(json.dumps(valid), encoding="utf-8")
        check("manifest containment rejects outside paths", rejected(module, outside, root, "escapes"))

        manifest_link = root / "manifest-link.json"
        manifest_link.symlink_to(manifest)
        check("manifest symlinks are rejected", rejected(module, manifest_link, root, "symlink"))

        symlink_asset = root / "linked.glb"
        symlink_asset.symlink_to(asset)
        symlink_value = fixture_manifest(module, symlink_asset, asset__relative_path=symlink_asset.name)
        check("asset symlinks are rejected", rejected(module, write_manifest(root, symlink_value, "linked.json"), root, "symlink"))

        real_directory = root / "real-assets"
        real_directory.mkdir()
        nested_asset = real_directory / "nested.glb"
        nested_asset.write_bytes(asset.read_bytes())
        linked_directory = root / "linked-assets"
        linked_directory.symlink_to(real_directory, target_is_directory=True)
        nested_value = fixture_manifest(
            module,
            nested_asset,
            asset__relative_path="linked-assets/nested.glb",
        )
        check(
            "symlinked asset path components are rejected",
            rejected(module, write_manifest(root, nested_value, "nested-link.json"), root, "symlink"),
        )

        traversal = fixture_manifest(module, asset, asset__relative_path="../fixture.glb")
        check("asset traversal is rejected", rejected(module, write_manifest(root, traversal, "traversal.json"), root, "clean relative"))

        wrong_size = fixture_manifest(module, asset, asset__bytes=asset.stat().st_size + 1)
        check("asset byte-count mismatch is rejected", rejected(module, write_manifest(root, wrong_size, "wrong-size.json"), root, "byte count"))

        oversized = fixture_manifest(module, asset, asset__bytes=2 * 1024 * 1024 * 1024 + 1)
        check("declared asset size is bounded at 2 GiB", rejected(module, write_manifest(root, oversized, "oversized.json"), root, "bounded"))

        wrong_digest = fixture_manifest(module, asset, asset__sha256="0" * 64)
        check("asset digest mismatch is rejected", rejected(module, write_manifest(root, wrong_digest, "wrong-digest.json"), root, "sha-256"))

        huge_manifest = root / "huge.json"
        huge_manifest.write_text(" " * (16 * 1024 + 1), encoding="utf-8")
        check("manifest input is bounded at 16 KiB", rejected(module, huge_manifest, root, "bounded size"))

        root_link = Path(directory) / "private-link"
        root_link.symlink_to(root, target_is_directory=True)
        check("symlinked private roots are rejected", rejected(module, manifest, root_link, "real directory"))

        for profile in sorted(module.STUDY_PROFILES):
            candidate = write_manifest(root, fixture_manifest(module, asset, study_profile=profile), f"study-{profile}.json")
            check(f"closed study profile accepted: {profile}", module.load_and_validate(str(candidate), str(root))["study_profile"] == profile)
        for profile in sorted(module.RECONSTRUCTION_PROFILES):
            candidate = write_manifest(root, fixture_manifest(module, asset, reconstruction_profile=profile), f"reconstruction-{profile}.json")
            check(f"closed reconstruction profile accepted: {profile}", module.load_and_validate(str(candidate), str(root))["reconstruction_profile"] == profile)
        for profile in sorted(module.RENDERER_PROFILES):
            candidate = write_manifest(root, fixture_manifest(module, asset, renderer_profile=profile), f"renderer-{profile}.json")
            check(f"closed renderer profile accepted: {profile}", module.load_and_validate(str(candidate), str(root))["renderer_profile"] == profile)

        for key, value in (("study_profile", "arbitrary_4k"), ("reconstruction_profile", "res_2048"), ("renderer_profile", "cycles_full_loop")):
            candidate = write_manifest(root, fixture_manifest(module, asset, **{key: value}), f"reject-{key}.json")
            check(f"unreviewed profile rejected: {value}", rejected(module, candidate, root))

        injected = fixture_manifest(module, asset)
        injected["prompt"] = "execute arbitrary generated scene"
        check("extra manifest capabilities are rejected", rejected(module, write_manifest(root, injected, "extra.json"), root, "exactly"))

    source = STUDY_MODULE.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(STUDY_MODULE))
    roles = literal_assignment(tree, "ROLE_SETTINGS")
    stars = literal_assignment(tree, "STAR_LAYERS")
    check("semantic treatment is closed to five reviewed roles", set(roles) == {"skin", "hair", "wings", "cloth", "boots"})
    check("material controls stay within normalized bounds", all(0.0 <= value <= 1.0 for settings in roles.values() for value in settings.values()))
    check("layered stars are fixed and bounded", [layer[0] for layer in stars] == ["dim", "medium", "hero"] and sum(layer[1] for layer in stars) == 420)
    check("four fixed reviewed lights are present", all(name in source for name in ("A9_warm_key", "A9_neutral_fill", "A9_amber_rim", "A9_red_back")))
    check("orbit is exactly 12 seconds with no rendered duplicate endpoint", module.STUDY_PROFILES == {"baseline_720": {"width": 1280, "height": 720, "fps": 30, "frames": 360}, "polished_1080": {"width": 1920, "height": 1080, "fps": 30, "frames": 360}} and 'profile["frames"] + 1' in source and "scene.frame_end = profile[\"frames\"]" in source)
    check("four-angle review exposes the full orbit", "[1, 91, 181, 271]" in source)
    check("AgX and reviewed glow remain deterministic", '"AgX - Medium High Contrast"' in source and 'set_node_input(glow, "Type", "Bloom")' in source and "import random" not in source)
    check("study lifecycle terminates for human review", '"lifecycle_state": "blocked_for_human_review"' in source and '"mutation_authority": "none"' in source)
    check("study imports only the verified process-local asset", 'bpy.ops.import_scene.gltf(filepath=validated["_verified_asset_path"])' in source)
    forbidden = ("subprocess", "socket", "requests", "urllib", "http://", "https://", "cron", "daemon", "systemd", "winner")
    check("study has no network, process, persistence, or winner-selection capability", not any(token in source.lower() for token in forbidden))
    run_cycles_contract(tree, module.ValidationError)

    review = REVIEW.read_text(encoding="utf-8")
    headings = (
        "## What was implemented",
        "## Files changed",
        "## Commands and deterministic results",
        "## Live qualification evidence",
        "## Local LLM evaluation",
        "## Memory and lifecycle",
        "## Risk classification",
        "## Known weaknesses",
        "## Human review checklist",
    )
    check("human review packet contains required sections", all(heading in review for heading in headings))
    check("review packet preserves the human visual gate", "blocked_for_human_review" in review and "does not select" in review)
    print("Blender generated-asset fidelity A9 checks passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CheckFailure, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        raise SystemExit(1)
