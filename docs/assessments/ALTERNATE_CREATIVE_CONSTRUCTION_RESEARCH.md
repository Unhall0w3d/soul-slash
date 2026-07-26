# Alternate Creative Construction Research

## Question

Can Soul move beyond flattened image/video and mixed-audio outputs by producing
editable Blender scenes, Unity scenes, or DAW-compatible multitrack music—and
would that be worthwhile on the durable host?

Reference hardware remains:

- Radeon RX 6900 XT, 16 GiB
- GeForce GTX 1070, 8 GiB
- Ryzen 7 5800X
- 64 GiB DDR4

No conclusion assumes a GPU upgrade.

## Recommendation

1. **Blender scene packages are the strongest next alternate visual path.**
2. **DAW interchange packages are a strong music path, but direct `.flp`
   generation is not the right contract.**
3. **Unity is technically possible but does not currently earn its additional
   editor, licensing, project, and learning complexity.**
4. **A selectively loaded 30B-class sparse coding model may deserve a later
   bake-off; dense 70B CPU-offloaded operation does not. Cloud Core is a better
   rare-use escalation for complex planning.**

## A visual escalation ladder

Soul should choose the least complex medium that can carry the intended visual
story:

1. **Still:** composition, color, symbol, and pose carry the piece.
2. **Short generated loop:** one atmospheric motion carries it.
3. **Longer generated loop:** the scene needs a small temporal arc.
4. **Constructed 3D shot:** persistent geometry, exact camera travel, physical
   lighting, occlusion, or repeatable blocking is materially important.

The fourth step should produce both the rendered companion and its editable
source scene. It should not require the Operator to learn an engine to complete
the ordinary Dashboard flow.

## Blender

### Feasibility: high for procedural and assembled scenes

Blender's Python API can construct objects, materials, lights, cameras,
animation, and save the result in Blender's native database. Blender also
supports background Python execution and animation rendering. Existing research
systems already translate natural language into Blender code; SceneCraft reports
complex scenes with up to one hundred assets, while Infinigen produces editable
procedural indoor and natural scenes and native `.blend` output.

The RX 6900 XT belongs to Blender's officially supported AMD RX 6000 class for
HIP Cycles rendering. A local pilot would still need to qualify the exact Arch,
Mesa/HIP, Blender, Eevee, and Cycles combination.

### The safe Soul architecture

Soul should not execute arbitrary model-authored Python directly. Blender Python
is unrestricted code and Blender itself warns that scripts carry security risk.

Use a compiled path:

1. Soul drafts a bounded declarative **scene specification**:
   - approved asset references;
   - primitive geometry;
   - transforms;
   - materials;
   - lights;
   - camera and keyframes;
   - render profile and duration.
2. A deterministic validator rejects unknown fields, paths, assets, drivers,
   scripts, external URLs, and excessive object/frame/render bounds.
3. A repository-owned compiler translates that schema into reviewed `bpy`
   operations.
4. Blender produces:
   - an inspectable `.blend`;
   - a low-resolution still or playblast;
   - a bounded preview loop;
   - a separately approved final render.
5. Human review gates revision and binding to music.

This is particularly suitable for abstract void geometry, liminal corridors,
architectural environments, procedural materials, particles, portals, lighting
arcs, and controlled camera motion. It is less immediately suitable for
high-quality bespoke humanoids without an approved asset library.

### Asset-generation limitation

Current high-fidelity open 3D generators remain strongly CUDA-oriented.
TRELLIS.2 requires an NVIDIA GPU with at least 24 GiB. Hunyuan3D documents a
lighter geometry path but still names NVIDIA CUDA as its supported GPU platform.
Neither is a sensible local production dependency for this host.

Soul can still build good stylized scenes from procedural geometry, approved
assets, generated textures, and composition. Generative mesh creation should be
a later optional provider, not a prerequisite.

### Expected time

- scene-plan and schema validation: seconds to a few minutes;
- simple Eevee preview: seconds to minutes;
- 8–20 second final loop: minutes, depending on resolution, samples, geometry,
  effects, and engine;
- heavy Cycles/volumetric work: potentially tens of minutes or longer.

The pipeline must estimate frame count and run a one-frame benchmark before a
full render. It should refuse jobs whose estimate crosses the reviewed bound.

## Unity

### Feasibility: technically high, product fit currently low

Unity scenes and prefabs can be built through editor C# and run in batch mode
with a repository-owned `-executeMethod` entry point. Unity's current AI surface
also advertises a project-aware Assistant, asset generators, and an official MCP
server that understands scene graphs and GameObjects.

That proves the concept, but it introduces:

- a large additional editor and versioned project;
- Unity account, trial/subscription, credit, and generated-asset metadata
  considerations for Unity AI;
- asset GUID, package, render-pipeline, and project-version coupling;
- another runtime and integration surface to qualify;
- complexity optimized for interactive applications rather than rendered music
  companions.

Use Unity only if Soul later needs an interactive world, real-time operator
navigation, game logic, or a reusable live stage. For a repeatable cinematic
shot, Blender is the smaller and more open construction target.

## FL Studio and multitrack music

### Feasibility: high for interchange, low for native `.flp`

The correct contract is not “Soul writes an FL Studio project file.” The native
format is application-specific and does not provide the stable, public authoring
contract Soul needs.

The portable deliverable should instead be a **DAW interchange package**:

- full-resolution master;
- one WAV or FLAC per audio stem, all beginning at time zero;
- multitrack Standard MIDI where symbolic parts exist;
- tempo and time-signature map;
- key and section-marker data;
- lyrics and vocal timing;
- dry/wet or effect guidance where available;
- a manifest with sample rate, bit depth, bar/beat alignment, hashes, and rights;
- import instructions for FL Studio.

FL Studio officially imports multitrack MIDI and can start a new project from
it. Its MIDI tracks conventionally represent separate instruments. Stems can
then occupy separate mixer/playlist channels.

### Native generation versus separation

There are three different quality levels:

1. **Post-hoc source separation** of Soul's mixed candidate. Fastest to add, but
   separated tracks can contain bleed and artifacts and are not the underlying
   performance.
2. **Symbolic multitrack composition** as MIDI, rendered through selected
   instruments. Highly editable and structurally exact, but sound quality
   depends on the instrument and effects library.
3. **Model-native track generation.** Best long-term fit when supported by the
   production runtime.

ACE-Step already documents track-oriented capabilities such as
`lyric2vocal` and `singing2accompaniment`; its roadmap also identifies a
multi-track ControlNet/LoRA for individual instrument stems. The official
ACE-Step VST3 supports CPU, CUDA, Metal, and Vulkan plus multitrack management.
Soul's current `acestep.cpp` production path generates a finished mix and does
not yet expose a reviewed stem contract, so compatibility must be verified
rather than inferred from the upstream Python or VST surface.

DAWDreamer demonstrates that Python can construct and render effect/instrument
graphs with VST plug-ins, but plugin availability and reproducibility would need
their own public-dependency policy.

### Recommended music sequence

1. Add a source-separation research pilot and measure bleed on kept Soul songs.
2. Define the DAW interchange manifest and FL Studio import review.
3. Audit current ACE-Step 1.5 Vulkan support for track generation and its
   official VST3 path.
4. Add symbolic MIDI only for genres and instruments where note-level control is
   genuinely useful.
5. Do not promise native `.flp` output.

## A local “Uber Core”

### What a larger model can and cannot solve

A larger LLM can improve:

- scene decomposition;
- spatial/camera planning;
- Blender schema drafting;
- revision reasoning;
- structured MIDI and orchestration planning;
- code repair.

It does not itself solve mesh quality, animation, rendering, instrument
performance, mixing, or source separation.

### Sensible candidate class

A sparse 30B-class coding model is the upper local class worth considering.
Qwen3-Coder 30B-A3B activates about 3.3B parameters per token. A Q4 GGUF is
roughly 18–19 GiB, so most weights can use the RX 6900 XT while a small remainder
and context use system memory. This is materially more plausible than a dense
70B Q4 model whose roughly 40+ GiB weight set would place most inference behind
the 5800X and DDR4 memory bandwidth.

Any such Core should be:

- manually selected or explicitly requested for a qualifying workflow;
- unloaded when the bounded task ends;
- benchmarked on actual scene-schema and multitrack-planning cases;
- rejected if it does not materially beat Daily Core per wall-clock minute;
- unavailable while AMD is reserved for music or visual generation.

### Current recommendation

Do not install an Uber Core yet. First build a small Blender schema/compiler
prototype using Daily Core or a human-authored fixture. That reveals whether the
limiting factor is planning, assets, rendering, or the schema. If complex scene
planning is the measured bottleneck, compare:

1. Daily Core Gemma;
2. a transient Qwen3-Coder 30B-A3B Q4 local profile;
3. Cloud Core in candidate-only mode.

Cloud Core is likely to deliver the best rare-use scene/code reasoning without
turning every attempt into a long CPU-offloaded inference. Local Uber remains
valuable only if privacy, offline operation, or repeated volume justifies its
latency and storage.

## Primary references

- [Blender Python API quickstart](https://docs.blender.org/api/dev/info_quickstart.html)
- [Blender command-line background rendering](https://docs.blender.org/manual/ja/5.0/advanced/command_line/arguments.html)
- [Blender scripting security](https://docs.blender.org/manual/sr/4.0/advanced/scripting/security.html)
- [Blender AMD GPU rendering support](https://docs.blender.org/manual/de/3.0/render/cycles/gpu_rendering.html)
- [SceneCraft research](https://arxiv.org/abs/2403.01248)
- [Infinigen](https://github.com/princeton-vl/infinigen)
- [Unity AI overview](https://unity.com/blog/unity-ai-how-to-get-started)
- [Unity command-line `executeMethod`](https://docs.unity.cn/430/Documentation/Manual/CommandLineArguments.html)
- [TRELLIS.2 requirements](https://github.com/microsoft/TRELLIS.2)
- [Hunyuan3D 2](https://github.com/Tencent-Hunyuan/Hunyuan3D-2)
- [FL Studio MIDI import](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/automation_midiimport.htm)
- [ACE-Step](https://github.com/ace-step/ACE-Step)
- [ACE-Step VST3](https://github.com/ace-step/acestep.vst3)
- [DAWDreamer paper](https://arxiv.org/abs/2111.09931)
- [MusicGen-Stem paper](https://arxiv.org/abs/2501.01757)
- [Qwen3 model architecture](https://qwenlm.github.io/blog/qwen3/)
