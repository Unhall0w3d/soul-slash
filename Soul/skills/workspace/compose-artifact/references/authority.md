# Authority and compatibility boundary

This package names the public capability `workspace.artifact.compose`. The
existing approval token remains internally bound to `artifact.create_revision`
for compatibility with pending Phase 11C operations. Do not introduce a second
token identity, migrate pending tokens silently, or duplicate the writer.

Preview performs one bounded local-provider draft and no artifact-file write.
Execution requires the preview's unexpired single-use token, exact chat, bound
operation scope, and literal `confirm`. The scope includes operation ID/type,
target, content digest and size, privacy, chat, provider, source identity and
digest, and optional grounding evidence.

Output is exactly one new UTF-8 `.md`, `.txt`, or `.json` file below the fixed
`artifacts/` root, at most 256 KiB and 4,000 lines. Reject overwrite, absolute
paths, traversal, symlinks, missing nested parents, invalid JSON, binary text,
and unsupported formats. Use exclusive no-follow creation, then verify bytes,
size, digest, and file identity before canonical registration and attachment.

Revision never changes its source and cannot reduce source privacy. Use only
local provider classes. No cloud fallback, direct edit, rich document, code,
executable, media, archive, multi-file package, publication, background worker,
watcher, service, schedule, or automatic retry belongs to this skill.
