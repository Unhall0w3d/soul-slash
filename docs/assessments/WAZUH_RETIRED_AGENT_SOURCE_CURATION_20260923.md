# Wazuh retired-agent status source curation — 2026-09-23

Status: source candidate for human merge review. The owner previously approved
retiring one decommissioned device while retaining its Wazuh history. This
curation did not alter Wazuh enrollment, keys, mappings, services or alerts.

The status collector validates optional retired agent IDs, rejects duplicates
and overlap with active device mappings, excludes retired agents from active
health counts, and returns them separately as historical evidence. With no
retirement IDs configured, the prior active summary remains unchanged.

The deterministic Wazuh security-status verifier covers normal collection,
retirement handling and invalid configuration. It passed under the project
Ruby. The owner-private integration manifest and specific agent identity stay
outside public source history.
