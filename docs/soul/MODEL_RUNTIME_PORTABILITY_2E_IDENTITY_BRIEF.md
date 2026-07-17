# Model Runtime Portability 2E — Runtime Identity and Neutral Alias Brief

```text
brief_status: approved by human owner instruction
implementation_authorized: yes
slice: Model Runtime Portability 2E
target: current local Linux machine
reboot_required: no
model_service_restart_authorized: idle-gated active profile only
dashboard_service_restart_authorized: yes, after local alias configuration changes
automatic_switch_or_fallback_authorized: no
```

## Purpose

Separate the truthful identity of each local model profile from the shared
OpenAI-compatible transport alias. Replace the Qwen-specific compatibility
alias with the neutral `soul-local-chat`, expose the actual loaded model and
accelerator in the dashboard, and show whether the selected-profile startup
policy is enabled.

## Approved profile identities

```text
nvidia-fallback
  model: Qwen3 8B Q4_K_M
  accelerator: NVIDIA CUDA

amd-quality
  model: Ministral 3 14B Instruct 2512 Q4_K_M
  accelerator: AMD Vulkan
```

The shared API alias is `soul-local-chat`. It is a stable endpoint contract, not
a claim about which model is loaded. The dashboard and application projection
must label it explicitly as an API alias.

## Runtime projection

The bounded status operation may add:

- profile-owned `model_name` and `accelerator` fields;
- top-level active `model_name`, `accelerator`, and `api_alias` fields;
- selected-at-login profile ID;
- the allowlisted `soul-model-runtime-selected.service` enablement state.

Startup inspection is read-only. An unavailable selector state does not make an
otherwise healthy model runtime unavailable and grants no mutation authority.

## Coordinated local cutover

The cutover is a bounded foreground operation with an exact preview digest and
confirmation. It may update only:

```text
<project>/.env
~/.config/systemd/user/soul-model-amd.service
~/.config/systemd/user/llama-server.service.d/override.conf
```

It must:

- accept only the reviewed old and new aliases;
- require regular non-symlink files at the exact paths;
- disclose hashes and paths without returning private file content;
- prove exactly one runtime active, zero Soul leases, zero active/deferred llama
  requests, reachable slots, and ready health before stopping it;
- revalidate the preview digest immediately before mutation;
- replace exactly the alias assignment in each file without changing model
  paths or other arguments;
- reload the systemd user manager;
- restart only the profile that was active before the cutover;
- verify `/v1/models` advertises only the neutral alias with at most twelve
  bounded foreground readiness attempts;
- restart the already-approved dashboard service so it reloads `.env`;
- roll all three files back and restore the previous active runtime if any step
  fails after mutation begins.

The operation terminates `complete`, `failed`, `awaiting_input`, `canceled`, or
`blocked_for_human_review`. It adds no daemon, watcher, timer, polling loop,
listener, service, automatic fallback, or automatic model switching.

## Documentation boundary

Current setup and runtime documentation moves to the neutral alias. Historical
assessments retain `soul-qwen3-8b-q4` where that was the actual advertised model
identifier during the recorded run.

## Human review checklist

- Dashboard distinguishes profile, actual model, accelerator, API alias, and service.
- Selected-at-login policy and profile are visible without granting controls.
- NVIDIA and AMD profiles advertise the same neutral API alias.
- Active AMD/Ministral returns healthy after one idle-gated service restart.
- Dashboard reload preserves authentication and reports the active runtime.
- No system reboot, automatic switching, fallback, or unrelated service mutation occurred.
