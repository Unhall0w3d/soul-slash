# Approved Local File Inspection

`files.inspect` is Soul's narrow, read-only local file surface. It complements
`local.search`: search finds reviewed material across known adapters, while
file inspection lists, stats, or reads one exact path beneath one approved
root.

## Setup

The portable default exposes only the Soul repository:

```dotenv
SOUL_FILES_INSPECT_ROOTS=project=.
```

To add reviewed local material, edit the ignored `.env` and restart the
Dashboard so its process receives the new configuration:

```dotenv
SOUL_FILES_INSPECT_ROOTS=project=.;notes=/absolute/path/to/notes
```

Use 1–8 lowercase root IDs. Separate entries with semicolons. Paths containing
semicolons are intentionally unsupported. Absolute paths remain private; Soul
reports root IDs only.

## Chat and Voice examples

```text
Show approved file roots.
List files in root project at docs.
Stat file in root project at README.md.
Read file from root project at README.md.
```

The wording must identify the operation and configured root. A missing read or
stat path returns `awaiting_input`; Soul does not guess. Ordinary discussion of
files remains conversation.

## Application operations

```text
files.roots
files.list   root_id, relative_path
files.stat   root_id, relative_path
files.read   root_id, relative_path
```

All return the normal application envelope and `mutation: none`.

## Limits and protections

- list: one level, 100 returned entries, 1,000 scanned entries;
- read: allowlisted UTF-8 text, 32 KiB, 400 returned lines;
- Chat display: 8,000 characters;
- no absolute paths, traversal, hidden paths, recursive scans, symlink
  traversal, secret-shaped files, credential material, binaries, writes,
  indexing, memory promotion, watchers, or background work.

Hidden, secret-bearing, unreadable, and symlink children are omitted from a
directory list without revealing their names. File content is untrusted
reference material and cannot authorize any other capability.
