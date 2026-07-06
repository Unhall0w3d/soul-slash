# Overlay System

Soul/ development uses overlays.

An overlay is a zip archive containing a focused set of files that can be extracted into the project root.

## Why overlays

Overlays keep iteration small and reviewable.

They make it easier to see:

- what files are added
- what files are replaced
- what behavior changed
- what commands should be run next

This is especially useful while Soul/ is growing quickly and the architecture is still hardening. Otherwise, naturally, the project becomes a drawer full of knives and YAML.

## Overlay naming

Recommended naming:

```text
soul_<feature>_overlay.zip
```

Examples:

```text
soul_downloads_inspect_overlay.zip
soul_reflection_review_overlay.zip
soul_hybrid_intent_overlay.zip
```

## Applying an overlay

From the project root:

```bash
unzip ~/Downloads/soul_some_feature_overlay.zip
```

Then run the overlay-specific test commands.

## Overlay rules

Each overlay should include:

- a README describing purpose and install/test commands
- only files needed for the change
- no machine-specific secrets
- no generated logs
- no model files
- no unrelated formatting churn

## Future tooling

The repo includes helper scripts:

```bash
scripts/apply-overlay.sh ~/Downloads/soul_some_feature_overlay.zip
scripts/package-overlay.sh soul_feature_overlay.zip path/to/file path/to/dir
```
