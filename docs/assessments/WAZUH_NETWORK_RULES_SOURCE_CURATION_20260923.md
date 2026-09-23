# Wazuh network-device rules source curation — 2026-09-23

Status: source candidate for human merge review. The owner's earlier review
records explicit deployment approval, manager-side validation and a live indexed
switch event. This curation did not contact Vigil, restart Wazuh or generate an
event.

The fixed decoder recognizes the reviewed vendor message shape. Four custom
rules classify routine, warning/error and repeated SNMP-authentication events.
They add no Active Response, notification, credential, device-control or raw
archive authority. The reviewed receiver, forwarding and firewall setup is a
separate cohort; these XML rules do not install it.

`make verify-wazuh-network-device-rules` parses the XML and checks rule IDs,
precedence, severity and the absence of response commands. It passed with the
project Ruby. The original host-specific manager receipts remain in private
review material. A future deployment requires fresh manager preflight and
read-back at its own gate.
