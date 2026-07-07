#!/usr/bin/env bash
set -euo pipefail

mkdir -p docs/overlays/archive

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

  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git mv "$f" "$dest"
  else
    mv "$f" "$dest"
  fi
  printf 'Moved %s -> %s\n' "$f" "$dest"
done

# Remove internal branding notes from public docs if present.
# Assets remain under assets/brand/ because README still uses the header image.
if [ -d docs/branding ]; then
  if git ls-files --error-unmatch docs/branding >/dev/null 2>&1; then
    git rm -r docs/branding
  else
    rm -rf docs/branding
  fi
  printf 'Removed docs/branding/\n'
fi

printf '\nPublic repo hygiene cleanup complete. Review with:\n'
printf '  git status --short\n'
printf '  git diff -- README.md .gitignore .env.example docs/REPOSITORY_HYGIENE.md\n'
