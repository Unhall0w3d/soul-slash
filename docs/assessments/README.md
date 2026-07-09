
# Assessment Documentation

This directory contains engineering documentation for implemented Soul assessment phases.

Assessment docs should describe committed behavior, CLI commands, boundaries, and verification expectations.

## Appropriate content

```text
environment assessment behavior
model runtime assessment behavior
capability matrix behavior
improvement proposal behavior
alpha generation/review/gate behavior
phase-level assessment docs for committed features
```

## Inappropriate content

```text
generated runtime JSON
generated proposal folders
proposal-local alpha artifacts
temporary overlay application notes
local machine-specific paths
secrets or provider credentials
```

## Rule of thumb

If the document explains committed behavior, it belongs here.

If the document only explains how to apply an overlay ZIP, it belongs in the local download or, if curated, under `docs/overlays/`.
