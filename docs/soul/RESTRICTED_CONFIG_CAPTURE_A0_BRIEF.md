# Restricted configuration capture A0

The Operator approved proceeding with a bounded, explicitly invoked capture of
the reviewed Atelier audit, su, sudo logging, SNMP, and Alloy configuration.
Implement a fixed seven-file reader and an owner-private capture below the
existing Soul private backup coverage. Preserve original numeric ownership,
modes, timestamps, and content hashes as recovery metadata. Never change source
permissions or restore/promote files automatically.

The privileged reader accepts no path arguments, writes no system files, and
rejects symlinks in every path component, non-regular files, non-root ownership,
group/world writable files, oversize files, and detectable source drift.
The unprivileged caller uses an explicit graphical pkexec authorization and
captures output without printing contents. No service, timer, retained password,
new sudo rule, network access, or backup capture is permitted.

Use a new timestamped directory, private permissions, atomic completion, and a
bounded timeout. Fail without publishing a partial capture. Tests must verify
the allow-list, metadata/hash fidelity, unsafe-path rejection, and size bounds.
Candidate review precedes the privileged invocation. Future changes require a
new invocation; a one-time capture is not continuous protection.
