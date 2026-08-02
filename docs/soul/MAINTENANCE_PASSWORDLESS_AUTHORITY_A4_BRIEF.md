# Maintenance Passwordless Authority A4 Brief

> **Superseded for current operation by A11.** The historical A4 v3 combined
> unattended repository and AUR behavior is retired. A11 limits the root-owned
> helper to trusted pacman repositories, Flatpak, and separately gated reboot;
> AUR updates require a distinct interactive human review.

```text
date: 2026-07-28
human_authorization: approved in the active development conversation
implementation_authorized: yes
installation_authorized: no; exact root-owned deployment requires later review
live_execution_authorized: no; deterministic and native-vector tests first
risk: Class 5
```

## Objective

Remove the administrator-password prompt and routine package-manager
interaction from the already accepted Maven A2/A3 maintenance workflow without
storing, forwarding, replaying, or otherwise exposing the Operator's password.

The resulting flow remains:

```text
fresh native evidence
→ exact maintenance or maintenance-and-reboot preview
→ authenticated Operator click
→ visible audit terminal with deterministic prompt handling
→ fixed update transaction
→ terminal receipt
→ optional reviewed reboot and one-shot restoration
```

The button click authorizes the reviewed transaction and its exact unattended
prompt policy. It does not authorize a general shell, arbitrary package
operation, arbitrary executable, arbitrary argument vector, or model-generated
answer.

## Security tradeoff

Passwordless maintenance necessarily creates reusable local privilege for some
bounded operation. It cannot provide the same protection against a compromised
desktop-owner account that a fresh sudo challenge provides. Current Arch
guidance explicitly warns that any process running as a passwordless-authorized
user may invoke the allowed command.

A4 accepts that residual risk only for a root-owned, immutable, fixed-purpose
maintenance authority. It does not authorize:

- `NOPASSWD: ALL`;
- passwordless `/usr/bin/pacman`, `/usr/bin/yay`, `/usr/bin/flatpak`,
  `/usr/bin/systemctl`, a shell, an interpreter, or an editable repository
  script;
- a wildcard command forwarder;
- password or credential storage; or
- model-generated, inferred, or unrecognized package prompt answers.

The root-owned authority is the command in sudoers. Its installed content is
bound by a SHA-256 sudoers command digest and is not writable by the desktop
owner. Updating the repository does not update privileged code.

## Qualified host and tools

The first implementation is qualified for Maven only:

- owner: the exact invoking local desktop UID;
- host: the exact local hostname recorded during installation;
- sudo/visudo: 1.9.17p2 or a compatible newer version with command digests;
- yay: 13.0.1;
- pacman configuration: `/etc/pacman.conf`;
- package build root: the invoking owner's canonical `~/.cache/yay`;
- fixed system tools: `/usr/bin/pacman`, `/usr/bin/bsdtar`,
  `/usr/bin/flatpak`, and `/usr/bin/systemctl`.

An unsupported owner, host, tool path, version, configuration path, package
archive location, or argument shape fails closed.

## Root-owned deployment

One exact reviewed installer may place:

```text
/usr/local/libexec/soul-maintenance-authority
/etc/sudoers.d/90-soul-maintenance-authority
```

Required ownership and modes:

```text
root:root 0755 /usr/local/libexec/soul-maintenance-authority
root:root 0440 /etc/sudoers.d/90-soul-maintenance-authority
```

The sudoers entry names the exact owner, hostname, root run-as identity,
installed authority path, and SHA-256 command digest. Installation:

1. previews exact helper and sudoers content plus their digests;
2. requires `INSTALL_SOUL_MAINTENANCE_AUTHORITY`;
3. requests privilege once for installation;
4. writes temporary root-owned files;
5. validates the sudoers file with `/usr/sbin/visudo -cf`;
6. atomically replaces only the two declared destinations;
7. verifies owner, mode, digest, and `sudo -n` status; and
8. terminates.

There is no service, daemon, timer, socket, watcher, background loop, or
long-running privileged process.

Uninstallation requires `REMOVE_SOUL_MAINTENANCE_AUTHORITY`, removes only the
exact installed files, and verifies that passwordless status is gone.

## Allowed privileged operations

The authority accepts only a fixed operation token and one validated
transaction ID. It accepts no executable, package target, package path,
package-manager flag, shell fragment, or free-form argument. It never invokes a
shell.

### Pacman calls emitted by qualified yay

The root-owned authority starts the exact qualified yay binary with the
original desktop identity supplied through sudo's trusted `SUDO_UID` and
`SUDO_USER` fields. Yay 13's upstream privilege boundary keeps pacman
privileged while dropping makepkg/build commands back to that original user.
The helper sets a fixed owner HOME and build root and supplies no user-provided
package target.

A deterministic, version-qualified option policy handles only routine
full-upgrade decisions:

```text
clean build: no
show diffs: no
edit PKGBUILD: no
upgrade the exact reviewed set: all
remove make dependencies after build: no
proceed with the exact reviewed transaction: yes
```

The qualified command uses yay's own versioned noninteractive and answer
options. It does not scrape terminal output or synthesize keystrokes. A changed
target set, provider choice, package replacement/removal, dependency conflict,
signing-key import, integrity exception, or package-manager error that yay or
pacman cannot resolve under those fixed defaults stops the transaction. The
model is never asked to choose.

The helper itself chooses exactly `-Syu` or `-Syyu` from the sealed transaction.
Yay remains responsible for its internal pacman calls; none are exposed through
sudoers or accepted from the caller. Build products remain beneath the
canonical owner yay build root.

A4 does not permit:

- any package target supplied by Dashboard, Chat, Voice, model output,
  environment, URI, transaction arguments, or direct helper invocation;
- `--root`, `--sysroot`, alternate database, configuration, hook, cache,
  GPG, log, or sandbox paths;
- `--nodeps`, `--dbonly`, `--noscriptlet`, `--overwrite`, downgrade, explicit
  package removal, orphan cleanup, cache cleanup, or arbitrary local package
  installation; or
- direct passwordless invocation of yay or pacman.

Automatic make-dependency removal remains disabled in A4. Selecting an
unexpected future yay version fails closed before the operation begins.
`--noconfirm` is permitted only inside the immutable, target-free,
version-qualified full-upgrade vector; it is never accepted from a caller.

After a successful AUR archive installation, qualified yay may invoke exactly
this bounded package-database bookkeeping shape to preserve the reviewed
package as explicitly installed:

```text
/usr/bin/pacman -D --asexplicit -q --noconfirm --config /etc/pacman.conf -- <package-name>...
```

This exception accepts one to 128 syntactically valid package names only while
the exact active yay PID remains bound to the reviewed transaction. It accepts
no other `-D`/`--database` operation, alternate path, install-reason action, or
caller-selected vector. The bookkeeping call cannot install, remove, upgrade,
or downgrade package contents.

### System Flatpak update

Only this exact operation is permitted:

```text
/usr/bin/flatpak update --system --noninteractive
```

Its ordinary exact-update confirmation may be accepted automatically. A remote
change, repair question, application-specific decision, removal, alternate
installation, override, or unfamiliar prompt stops for human review. No
application ID or extra operation argument is accepted.

### Reboot

Only the accepted A3 coordinator may request:

```text
/usr/bin/systemctl reboot
```

The authority requires the exact live-reboot transaction capsule and durable
`reboot_requested` journal state. It cannot reboot from A2, Chat, Voice,
direct helper invocation, stale state, or an arbitrary file.

## Transaction capsule

Passwordless authority does not replace A2/A3 authorization.

Before the terminal handoff, the existing services still validate:

- authenticated Operator click;
- exact plan and native-evidence digests;
- owner and request identity;
- replay and deadline;
- package lock and disk thresholds;
- active Soul work;
- A2 versus A3 authority; and
- resume-unit, restore-registry, boot-ID, and reboot preconditions.

The root-owned authority additionally validates a minimal capsule:

- schema and transaction ID;
- owner UID and source boot ID;
- A2 or A3 mode;
- plan digest and deadline;
- exact allowed operation phase;
- one-use operation counter; and
- root-owned runtime state binding the phase to the active foreground
  transaction.

Every privileged call either advances the capsule monotonically or terminates
it. Replays, phase regression, concurrent callers, unexpected parents,
deadline expiry, terminal loss, and changed boot identity fail closed.

## Unattended decision behavior

The visible terminal remains an audit and cancellation surface. There is no
prompt-scraping responder. The root-owned helper supplies only yay 13.0.1's
reviewed native policy options and Flatpak's native noninteractive option:

```text
--noconfirm
--answerclean None
--answerdiff None
--answeredit None
--answerupgrade All
--noremovemake
```

These constants mean “no” to clean rebuilds, diffs, PKGBUILD editing, and
make-dependency removal; “all” to the already reviewed upgrade set; and “yes”
to proceeding with that exact full upgrade. They are not executable input,
paths, package targets, or authority for another phase. They cannot be changed
by Chat, Voice, a model, retrieved text, the Dashboard request, environment
variables, or package output.

Closing the terminal, receiving contradictory package evidence, encountering
an unresolved package-manager decision, or receiving a nonzero tool result
terminates `failed`, `canceled`, or `blocked_for_human_review`. Nothing retries
automatically.

## Lifecycle and receipts

```text
planned
→ reviewed
→ authority_checked
→ updates_running
→ updates_verified
→ complete

A3 only:
updates_verified
→ snapshot_recorded
→ reboot_requested
→ awaiting_login
→ restoring
→ complete
```

Receipts add:

- authority mode (`native_prompt` or `root_owned_passwordless`);
- installed-authority digest;
- accepted privileged operation identifiers;
- rejected operation identifier and reason, when applicable; and
- password prompts (`0` for the installed passwordless path).

They store no password, terminal input, package contents, arbitrary command
line, environment, token, or sudoers content.

## Deterministic acceptance

Tests must prove:

- the public default remains native password authentication;
- passwordless mode is unavailable unless both root-owned artifacts are exact;
- installer preview is deterministic and installation requires exact
  confirmation;
- sudoers content grants only the digest-bound authority path;
- helper input is an argument array and never a shell string;
- qualified yay refresh, upgrade, archive-install, and install-reason shapes
  pass;
- arbitrary commands, package targets, paths, options, archives, phases,
  owners, hosts, parents, replays, and stale capsules fail before execution;
- routine clean-build, diff, edit, make-dependency, exact-set, and proceed
  prompts receive only their fixed policy answers;
- provider selection, package removal/replacement, key import, conflict,
  integrity exception, and unknown-prompt fixtures fail closed;
- Flatpak system update and A3 reboot retain exact independent gates;
- A2 remains unable to reboot;
- cancellation and failure terminate the capsule;
- no privileged process survives a terminal lifecycle; and
- all A1/A2/A2B/A3 regressions continue to pass.

## Human acceptance

1. Review this brief and the implementation/review artifact.
2. Inspect the exact installed helper and sudoers preview.
3. Run deterministic and unprivileged native-vector probes.
4. Approve one root-owned installation.
5. Confirm arbitrary-command probes are rejected.
6. Run one supervised no-update or low-change A2 transaction with zero
   password prompts or routine human answers.
7. Run one later supervised A3 transaction and inspect restoration.
8. Keep, revise, or uninstall the authority.

Passing tests does not authorize installation or live execution.

## Sources

- [sudoers manual](https://www.sudo.ws/docs/man/1.9.14/sudoers.man.pdf)
- [ArchWiki sudo guidance](https://wiki.archlinux.org/title/Sudo)
- [polkit authorization reference](https://polkit.pages.freedesktop.org/polkit/eggdbus-interface-org.freedesktop.PolicyKit1.Authority.html)
- [yay upstream repository](https://github.com/Jguer/yay)
- [yay sudo-loop security discussion](https://github.com/Jguer/yay/issues/2170)
