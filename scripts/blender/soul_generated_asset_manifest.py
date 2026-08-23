#!/usr/bin/env python3
"""Validate the closed A9 private generated-asset manifest contract.

The manifest is deliberately a receipt for one already-retained GLB, not an
import format.  It contains no command, URL, shader graph, or executable
content.  Both its own location and the referenced asset must stay below the
configured private root.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import tempfile
from pathlib import Path


SCHEMA_VERSION = "soul.blender.generated-asset.a9.v1"
ASSET_ID = re.compile(r"[a-z][a-z0-9_-]{2,63}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
STUDY_PROFILES = {
    "baseline_720": {"width": 1280, "height": 720, "fps": 30, "frames": 360},
    "polished_1080": {"width": 1920, "height": 1080, "fps": 30, "frames": 360},
}
RECONSTRUCTION_PROFILES = {"res_1024", "res_1536_geometry", "res_1536_textured"}
RENDERER_PROFILES = {"eevee_preview", "cycles_probe_64", "cycles_probe_128"}


class ValidationError(ValueError):
    """Raised when an untrusted manifest cannot be admitted to the study."""


def _regular_file(path: Path, label: str) -> None:
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ValidationError(f"{label} must be a regular non-symlink file")


def _reject_symlink_components(root: Path, candidate: Path, label: str) -> None:
    """Reject a symlink anywhere in the caller-controlled lexical path."""
    root_real = root.resolve(strict=True)
    candidate_lexical = Path(os.path.abspath(candidate))
    try:
        relative = candidate_lexical.relative_to(root_real)
    except ValueError as error:
        raise ValidationError(f"{label} lexically escapes configured private asset root") from error
    current = root_real
    for component in relative.parts:
        current /= component
        if current.is_symlink():
            raise ValidationError(f"{label} path contains a symlink")


def _within(root: Path, candidate: Path, label: str) -> Path:
    root_real = root.resolve(strict=True)
    candidate_real = candidate.resolve(strict=True)
    try:
        candidate_real.relative_to(root_real)
    except ValueError as error:
        raise ValidationError(f"{label} escapes configured private asset root") from error
    return candidate_real


def _relative_path(value: object) -> str:
    if not isinstance(value, str) or not value or len(value) > 240:
        raise ValidationError("asset.relative_path must be a bounded string")
    path = Path(value)
    if path.is_absolute() or "\\" in value or any(part in {"", ".", ".."} for part in path.parts):
        raise ValidationError("asset.relative_path must be a clean relative path")
    if path.suffix.lower() != ".glb":
        raise ValidationError("asset.relative_path must name a GLB")
    return value


def _exact_keys(value: object, expected: set[str], label: str) -> dict:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValidationError(f"{label} must contain exactly: {','.join(sorted(expected))}")
    return value


def load_and_validate(manifest_path: str, asset_root: str) -> dict:
    """Return a normalized manifest plus the verified private GLB path.

    No returned receipt includes either private absolute path; the builder keeps
    that value process-local while it imports the verified file.
    """
    root = Path(asset_root)
    if not asset_root or not root.is_dir() or root.is_symlink():
        raise ValidationError("configured private asset root must be a real directory")
    # Check the lexical file before resolving containment: checking only the
    # resolved target would silently admit a symlink supplied by the caller.
    manifest_candidate = Path(manifest_path)
    _reject_symlink_components(root, manifest_candidate, "manifest")
    _regular_file(manifest_candidate, "manifest")
    manifest_file = _within(root, manifest_candidate, "manifest")
    if manifest_file.suffix.lower() != ".json":
        raise ValidationError("manifest must be JSON")
    if manifest_file.stat().st_size > 16 * 1024:
        raise ValidationError("manifest exceeds bounded size")
    try:
        with manifest_file.open("r", encoding="utf-8") as handle:
            manifest = json.load(handle)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValidationError("manifest is unreadable JSON") from error

    manifest = _exact_keys(manifest, {"schema_version", "asset", "study_profile", "reconstruction_profile", "renderer_profile"}, "manifest")
    if manifest["schema_version"] != SCHEMA_VERSION:
        raise ValidationError("manifest schema_version is unsupported")
    asset = _exact_keys(manifest["asset"], {"id", "relative_path", "bytes", "sha256"}, "asset")
    if not isinstance(asset["id"], str) or not ASSET_ID.fullmatch(asset["id"]):
        raise ValidationError("asset.id is invalid")
    relative_path = _relative_path(asset["relative_path"])
    if not isinstance(asset["bytes"], int) or not 1 <= asset["bytes"] <= 2 * 1024 * 1024 * 1024:
        raise ValidationError("asset.bytes is outside the bounded GLB range")
    if not isinstance(asset["sha256"], str) or not SHA256.fullmatch(asset["sha256"]):
        raise ValidationError("asset.sha256 is invalid")
    if manifest["study_profile"] not in STUDY_PROFILES:
        raise ValidationError("study_profile is not a closed A9 profile")
    if manifest["reconstruction_profile"] not in RECONSTRUCTION_PROFILES:
        raise ValidationError("reconstruction_profile is not approved; res_2048 is prohibited")
    if manifest["renderer_profile"] not in RENDERER_PROFILES:
        raise ValidationError("renderer_profile is not a closed A9 renderer profile")

    asset_candidate = root / relative_path
    _reject_symlink_components(root, asset_candidate, "asset")
    _regular_file(asset_candidate, "asset")
    asset_file = _within(root, asset_candidate, "asset")
    if asset_file.stat().st_size != asset["bytes"]:
        raise ValidationError("asset byte count does not match manifest")
    digest = hashlib.sha256()
    with asset_file.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != asset["sha256"]:
        raise ValidationError("asset SHA-256 does not match manifest")

    return {
        "schema_version": SCHEMA_VERSION,
        "asset": {"id": asset["id"], "bytes": asset["bytes"], "sha256": asset["sha256"]},
        "study_profile": manifest["study_profile"],
        "reconstruction_profile": manifest["reconstruction_profile"],
        "renderer_profile": manifest["renderer_profile"],
        "dimensions": STUDY_PROFILES[manifest["study_profile"]].copy(),
        "_verified_asset_path": str(asset_file),
    }


def public_receipt(validated: dict) -> dict:
    """Render the safe public portion, never a private filesystem location."""
    return {key: value for key, value in validated.items() if key != "_verified_asset_path"}


def _self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        asset_file = root / "winged.glb"
        asset_file.write_bytes(b"glTF\x02\x00\x00\x00")
        digest = hashlib.sha256(asset_file.read_bytes()).hexdigest()
        manifest = {
            "schema_version": SCHEMA_VERSION,
            "asset": {"id": "winged-figure", "relative_path": "winged.glb", "bytes": asset_file.stat().st_size, "sha256": digest},
            "study_profile": "baseline_720", "reconstruction_profile": "res_1024", "renderer_profile": "eevee_preview",
        }
        manifest_file = root / "study.json"
        manifest_file.write_text(json.dumps(manifest), encoding="utf-8")
        assert load_and_validate(str(manifest_file), str(root))["asset"]["id"] == "winged-figure"
        manifest_link = root / "manifest-link.json"
        manifest_link.symlink_to(manifest_file.name)
        try:
            load_and_validate(str(manifest_link), str(root))
        except ValidationError:
            pass
        else:
            raise AssertionError("manifest symlink was admitted")
        alias = root / "alias"
        alias.symlink_to(root, target_is_directory=True)
        try:
            load_and_validate(str(alias / manifest_file.name), str(root))
        except ValidationError:
            pass
        else:
            raise AssertionError("manifest parent symlink was admitted")
        asset_link = root / "asset-link.glb"
        asset_link.symlink_to(asset_file.name)
        manifest["asset"]["relative_path"] = asset_link.name
        manifest_file.write_text(json.dumps(manifest), encoding="utf-8")
        try:
            load_and_validate(str(manifest_file), str(root))
        except ValidationError:
            pass
        else:
            raise AssertionError("asset symlink was admitted")
        manifest["asset"]["relative_path"] = f"{alias.name}/{asset_file.name}"
        manifest_file.write_text(json.dumps(manifest), encoding="utf-8")
        try:
            load_and_validate(str(manifest_file), str(root))
        except ValidationError:
            pass
        else:
            raise AssertionError("asset parent symlink was admitted")
        manifest["asset"]["relative_path"] = asset_file.name
        manifest["reconstruction_profile"] = "res_2048"
        manifest_file.write_text(json.dumps(manifest), encoding="utf-8")
        try:
            load_and_validate(str(manifest_file), str(root))
        except ValidationError:
            return
        raise AssertionError("res_2048 was admitted")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest")
    parser.add_argument("--asset-root")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        _self_test()
        print("SOUL_A9_MANIFEST_SELF_TEST=ok")
        return
    if not args.manifest or not args.asset_root:
        parser.error("--manifest and --asset-root are required")
    print(json.dumps(public_receipt(load_and_validate(args.manifest, args.asset_root)), sort_keys=True))


if __name__ == "__main__":
    main()
