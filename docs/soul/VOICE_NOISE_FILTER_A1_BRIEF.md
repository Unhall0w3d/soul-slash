# Voice Noise Filter A1 Brief

```text
date: 2026-07-24
human_authorization: explicitly approved in the active development conversation
implementation_authorized: yes
risk: Class 4 - persistent user audio configuration and bounded audio-stack restart
```

## Objective

Expose the installed RNNoise plugin as a mono PipeWire virtual microphone for
Soul and other local applications. Bind it to the reviewed physical source,
make it the default input, and activate it without a reboot.

## Authorized scope

- One generated user configuration:
  `~/.config/pipewire/pipewire.conf.d/99-soul-rnnoise.conf`.
- The installed `librnnoise_ladspa` plugin and `noise_suppressor_mono` label.
- One exact source node captured in the reviewed plan.
- One bounded restart of the existing `pipewire`, `pipewire-pulse`, and
  `wireplumber` user services.
- Set the resulting `effect_output.soul-rnnoise` source as the user default.
- Remove the new configuration and restart the audio stack if activation
  validation fails.

## Prohibitions

- No new service, daemon, listener, watcher, scheduler, or background loop.
- No arbitrary plugin, source, or destination path from unreviewed input.
- No overwrite of an existing configuration or symlink.
- No source monitoring, recording, audio retention, or network transmission.

## Required evidence

- exact digest and confirmation gate;
- generated mono filter is bound to the reviewed raw source;
- activation exposes the named source;
- default source changes only after successful activation;
- failure rolls back the generated file;
- public check/plan/install targets and operator documentation.
