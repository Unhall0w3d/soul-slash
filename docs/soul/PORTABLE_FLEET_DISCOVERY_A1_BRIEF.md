# Portable Fleet Discovery and Enrollment A1 Brief

## Human direction

Generalize Guided Maintenance so a public-repository user can explicitly
discover devices on a selected local subnet, review inert candidates, enroll
chosen devices into local state, and let Soul adapt to capabilities that are
actually present.

The supported package capability vocabulary is:

- pacman
- yay
- paru
- apt
- apt-get
- dnf
- zypper
- apk
- Flatpak
- Snap
- Nix

Detection must not assume one package manager from an OS or distribution name.
Several managers may coexist.

Windows is outside A1. A later Windows adapter will be developed against the
Operator's Windows container.

## Approved A1 scope

A1 may:

- accept one explicit RFC1918 IPv4 subnet between `/24` and `/32`;
- run one foreground, time-bounded, host-count-bounded discovery command after
  an authenticated button click or explicit CLI invocation;
- return live-address candidates without persisting the scan;
- distinguish addresses already represented by local fleet configuration;
- preview and execute enrollment of one exact device into an owner-private,
  bounded local registry;
- support `status_only` enrollment using bounded reachability;
- support `ssh` inventory enrollment only through one exact, already configured
  OpenSSH alias;
- collect an allowlisted OS/kernel/hostname projection and independently test
  allowlisted package-manager executable paths;
- show enrolled devices in fleet status as `inventory_only`, with no mutation
  buttons;
- preview and remove one exact enrolled registry record;
- expose dependency checking and one explicit scan through Makefile targets.

## Explicitly excluded

A1 must not:

- scan automatically on page load, on a timer, or in a background process;
- accept public, loopback, link-local, multicast, IPv6, or more-than-256-host
  networks;
- accept request-supplied executables, flags, ports, shell text, SSH options,
  usernames, passwords, keys, or arbitrary commands;
- authenticate to a discovered address automatically;
- infer that an open or responding address is trusted;
- enroll every discovery result automatically;
- grant maintenance, reboot, package-update, service-control, or root authority
  to a discovered or enrolled device;
- turn a detected package manager into an executable update plan;
- store scan output, MAC addresses, serial numbers, credentials, line identity,
  call history, or raw SSH output;
- add a service, daemon, watcher, timer, listener, or polling loop.

## Discovery contract

- Tool: fixed `/usr/bin/nmap`.
- Fixed arguments: ping/ARP host discovery, numeric addresses, bounded retry and
  host-time behavior.
- Input: one validated private subnet only.
- Maximum addresses: 256.
- Command timeout: 30 seconds.
- Result limit: 256 unique IPv4 addresses.
- Terminal lifecycle: `complete` or `failed`.
- Persistence: none.

## Enrollment contract

`status_only`:

- revalidates one private address with one bounded ping;
- records only configured identity and reachability semantics.

`ssh`:

- requires an exact literal `Host` entry in the selected owner SSH config;
- requires that alias's resolved `HostName` to equal the selected private
  candidate address;
- uses batch mode, a five-second connection timeout, and fixed commands;
- records allowlisted parsed facts only;
- detects package capabilities by fixed executable paths, independently of OS
  identity.

Both modes:

- bind an exact preview digest and confirmation phrase;
- write one private `0600` atomic registry only after exact revalidation;
- cap the registry at 64 records;
- never add mutation controls.

## Removal contract

Removal requires one exact record preview, digest, and confirmation. It removes
only the local enrollment record. It does not contact, modify, shut down, or
forget data on the device.

## Public/local boundary

Tracked source contains neutral defaults, supported capability definitions, and
deterministic fixtures. Subnets, addresses, aliases, discovered candidates,
enrollment records, credentials, projects, media outputs, and model files remain
ignored local state.

## Risk classification

Discovery and fingerprinting are Class 2 local-network reads. Enrollment and
removal are Class 2 owner-private registry mutations. No Class 5 device mutation
authority is introduced.
