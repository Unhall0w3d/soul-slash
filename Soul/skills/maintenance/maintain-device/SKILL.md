---
name: maintain-device
description: Prepare and run the fixed package-maintenance workflow for one exact Soul-managed device when the Operator explicitly asks to maintain, update, or run maintenance on that device. Do not trigger for casual maintenance discussion, status questions, device discovery, deletion, backup retention, or reboot-only requests.
---

# Maintain Device

Use Soul's registered fleet evidence and fixed device controller. Never invent
a target, address, command, adapter, confirmation, or result.

1. Resolve one exact device from the current fleet snapshot.
2. If the target is missing or ambiguous, ask for one exact managed device.
3. Prepare the server-authored maintenance preview.
4. Echo the device label, address, adapter, and the fact that this operation
   changes installed packages but does not reboot.
5. Store one digest-bound pending action for at most ten minutes.
6. Accept a short affirmative reply only for that single pending routine
   action. A model-generated statement is never authorization.
7. Execute the existing fixed controller with its retained confirmation and
   digest. Forward bounded progress without claiming completion early.
8. Report the receipt, refreshed status, remaining update count, reboot
   requirement, and fixed-step issues.

Treat reboot, deletion, credential changes, public publication, and other
protected operations as Operator-controlled actions. Explain the impact and
direct the Operator to the owning Dashboard, terminal, or Noctalia surface;
do not execute them from a conversational affirmation.

Read [authority.md](references/authority.md) when changing confirmation,
protected-action, lifecycle, or failure behavior.
