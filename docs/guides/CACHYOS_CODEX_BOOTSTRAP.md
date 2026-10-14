# CachyOS: restricted Codex bootstrap handoff

Status, 2026-10-14: proposed recovery procedure; source checkpoint only.
Inventory, private-state capture, backup, installation and restoration require
the operator's next go-ahead. This document is not that go-ahead.

## Purpose and stopping point

The operator wants a fresh CachyOS installation, the locally managed desktop
updater restored, then the rest of recovery coordinated in the existing desktop
chat. Do not turn the initial Codex CLI invocation into a general restore agent.
No automatic services, GPU/model work, project tests or migration continuation.

The real updater is `codex-update`; `update-codex` is the operator's informal
name unless an explicit alias is later established. Its reviewed source is in
[tools/codex-desktop-local](../../tools/codex-desktop-local/PRESERVATION.md).
It repackages the official binary as a local pacman package; it does not build
the desktop application from source or require Omarchy's repository.

## Required pre-reinstall preparation, not yet executed

1. Preserve the exact public source checkpoint and a known-good built desktop
   package/checksum in the independently verified recovery kit. Record the
   tested app/CLI versions; do not depend exclusively on a mutable latest feed.
2. Identify the actual current app and CLI state roots, the existing chat ID,
   session registry, attachments and referenced local files. Retain source
   paths/ownership and workspace mappings in the private recovery manifest.
3. Capture that state while the app and related writers are closed, using a
   reviewed consistent-copy method. SQLite files and any WAL/SHM companions
   must not be independently copied from an active writer and called consistent.
4. Keep conversations, credentials, cookies, tokens, keys and personal policy
   files encrypted and out of this public Git repository. Record what will be
   restored versus freshly authenticated; never put passwords in a command,
   prompt, chat or public manifest. Store recovery keys independently of the
   disk being erased and prove access before erasure.
5. Rehearse the minimal restore to a separate empty location. Validate archive
   integrity, expected session records and ownership without modifying the live
   profile or opening a second writer on it. A directory existing is not proof
   the application will index the desired chat after reinstall.

## Minimal new-system sequence

1. Operator installs CachyOS and establishes the chosen desktop, networking and
   local account. Preserve the original username/home path where practical;
   otherwise explicitly map paths. Do not replay Omarchy's package repositories,
   shell, boot arguments, `/etc` tree, or desktop configuration wholesale.
2. Operator installs/authenticates Codex CLI by the then-current supported route.
   Give it this bounded handoff rather than expecting a new empty session to
   reconstruct the previous conversation.
3. CLI obtains only the reviewed updater source at the recorded commit, copies
   it into the agreed writable Build directory, restores executable modes and
   command links, and checks its manifest plus offline tests. Inspect the actual
   CachyOS package state and the recipe's build/runtime requirements before
   proposing exact dependency installation. No full package-list restore.
4. CLI reports the exact command for the operator to run and **stops**. The
   operator runs `codex-update` and handles local sudo. Keep the known-good
   offline package as a reviewed fallback if upstream/build/network fails;
   never silently downgrade or replace the updater's trust model.
5. Before first desktop use, the operator follows the separately prepared
   private, deterministic chat-state restore instructions with the app closed.
   This narrow state restoration is a prerequisite for returning to the existing
   chat, not authority for CLI-driven restoration of Soul, games or the system.
6. Open the desktop app, authenticate if required, find the original chat, and
   confirm its latest migration handoff is visible. If it is absent, stop at the
   explicit bootstrap recovery gate; do not substitute a new chat and claim
   continuity was recovered. Resume broader work there only after confirmation.

## Short assignment for the first CLI session

> Restore only the reviewed local `codex-update` source, recipe, launcher and
> command links, with the minimum CachyOS prerequisites. Verify source hashes
> and offline parser/syntax tests. Do not run the updater, import broad user
> configuration, restore projects/services, change boot/network policy, start
> models, or resume paused work. Tell me the updater command to run, then stop.
> Private chat-state recovery follows the separately approved operator procedure.

## Important distinction

Codex CLI does support resuming saved local chats; it is not inherently without
conversation context. A fresh installation or a new session does not acquire
this history merely by installing the binary. The intentionally narrow CLI role
above remains the operator's chosen workflow. Official reference:
[Codex CLI saved-chat resume](https://learn.chatgpt.com/docs/codex/cli).

The Linux desktop packaging route and support matrix must be rechecked when
the install is actually performed; this local Arch recipe is not a promise of
official CachyOS support. References:
[OpenAI Linux desktop documentation](https://learn.chatgpt.com/docs/linux/linux-app),
[CachyOS installation guide](https://wiki.cachyos.org/installation/installation_on_root/).
