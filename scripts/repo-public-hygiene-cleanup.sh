#!/usr/bin/env bash
set -euo pipefail

mode="${1:---apply}"
if [ "$#" -gt 1 ] || { [ "$mode" != "--check" ] && [ "$mode" != "--apply" ]; }; then
  printf 'Usage: %s [--check|--apply]\n' "$0" >&2
  exit 2
fi

planned=0

record_move() {
  local source="$1"
  local destination="$2"
  planned=1
  if [ "$mode" = "--check" ]; then
    printf 'Would move %s -> %s\n' "$source" "$destination"
    return
  fi
  mkdir -p "$(dirname "$destination")"
  if git ls-files --error-unmatch "$source" >/dev/null 2>&1; then
    git mv "$source" "$destination"
  else
    mv "$source" "$destination"
  fi
  printf 'Moved %s -> %s\n' "$source" "$destination"
}

# Move root-level generated overlay/readme artifacts out of the repository root.
for f in README_*; do
  [ -e "$f" ] || continue
  [ "$f" = "README.md" ] && continue

  case "$f" in
    README_MISSING_LLM_INTENT_CLASSIFIER_FIX.md|README_RESTORE_LAST_CLEANUP.md)
      dest="docs/overlays/archive/$f"
      ;;
    README_*_OVERLAY.md|README_PUBLIC_*.md|README_MAKEFILE_*.md|README_RUNTIME_PROVIDER_DOCS_OVERLAY.md|README_REPO_BRANDING_README_UPDATE.md|README_README_GETTING_STARTED_UPDATE.md)
      dest="docs/overlays/archive/$f"
      ;;
    *)
      continue
      ;;
  esac

  record_move "$f" "$dest"
done

# Remove internal branding notes from public docs if present.
# Assets remain under assets/brand/ because README still uses the header image.
if [ -d docs/branding ]; then
  planned=1
  if [ "$mode" = "--check" ]; then
    printf 'Would remove docs/branding/\n'
  else
    if git ls-files --error-unmatch docs/branding >/dev/null 2>&1; then
      git rm -r docs/branding
    else
      rm -rf docs/branding
    fi
    printf 'Removed docs/branding/\n'
  fi
fi

if [ "$mode" = "--check" ]; then
  if [ "$planned" -eq 0 ]; then
    printf 'Public repo hygiene check passed; no cleanup actions are pending.\n'
    exit 0
  fi
  printf 'Public repo hygiene check found pending actions; no files were changed.\n' >&2
  exit 1
fi

printf '\nPublic repo hygiene cleanup complete. Review with:\n'
printf '  git status --short\n'
printf '  git diff -- README.md .gitignore .env.example docs/REPOSITORY_HYGIENE.md\n'
