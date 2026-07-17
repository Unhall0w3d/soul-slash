#!/usr/bin/env ruby
# frozen_string_literal: true

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

root = File.expand_path("..", __dir__)
architecture = File.read(File.join(root, "docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md"))
brief = File.read(File.join(root, "docs/soul/MULTI_MODEL_MUSIC_STUDIO_A0_BRIEF.md"))
review = File.read(File.join(root, "docs/assessments/MULTI_MODEL_MUSIC_STUDIO_A0_REVIEW.md"))
roadmap = File.read(File.join(root, "docs/ROADMAP.md"))
milestones = File.read(File.join(root, "docs/MILESTONES.md"))
current = File.read(File.join(root, "docs/CURRENT_STATE.md"))

puts "Soul multi-model and Music Studio A0 verification:"

check("topology assigns exact independent hardware lanes",
      architecture.include?("RX 6900 XT, 16 GiB") &&
        architecture.include?("GTX 1070, 8 GiB") &&
        architecture.include?("Ryzen 7 5800X and 62 GiB RAM"),
      errors)
check("AMD chat remains independent of NVIDIA music",
      architecture.include?("AMD conversation lane remains loaded during an NVIDIA music run") &&
        architecture.include?("nvidia-fallback and nvidia-music conflict"),
      errors)
check("lead and comparison candidates are explicit",
      architecture.include?("Lead: ACE-Step 1.5 turbo / 2B on NVIDIA") &&
        architecture.include?("Comparison: DiffRhythm 1.2") &&
        architecture.include?("YuE") && architecture.include?("MusicGen"),
      errors)
check("pilot measures full target duration rather than trusting vendor claims",
      architecture.include?("30-second instrumental generation") &&
        architecture.include?("90-second structured generation") &&
        architecture.include?("150–180-second song generation"),
      errors)
check("audio candidates retain a FLAC master and derived MP3 proxy",
      architecture.include?("48 kHz stereo FLAC") &&
        architecture.include?("MP3 listening proxy") &&
        architecture.include?("never a second model generation") &&
        architecture.include?("both paths, byte sizes, SHA-256 digests"),
      errors)
check("project storage is private and shared memory remains authoritative",
      architecture.include?("Soul/music/projects/<project-id>/") &&
        architecture.include?("never committed") &&
        architecture.include?("existing shared memory layer"),
      errors)
check("reference classes and provenance boundary are explicit",
      architecture.include?("Musical concepts") &&
        architecture.include?("Private inspiration notes") &&
        architecture.include?("Reference audio") &&
        architecture.include?("distills named inspiration into musical attributes"),
      errors)
check("generation lifecycle is foreground, bounded, and cancelable",
      architecture.include?("START_MUSIC_GENERATION") &&
        architecture.include?("sends TERM to its exact process group") &&
        architecture.include?("KILLs that") &&
        %w[complete failed awaiting_input canceled blocked_for_human_review].all? { |state| architecture.include?(state) },
      errors)
check("sequential dashboard limitation blocks premature tab",
      architecture.include?("A1 is CLI-only") &&
        architecture.include?("fire-and-forget workers are not acceptable shortcuts"),
      errors)
check("phases retain separate human gates",
      %w[A0 A1 A2 A3 A4 A5].all? { |phase| architecture.include?("### #{phase}") } &&
        roadmap.include?("[x] Music A1") && roadmap.include?("[ ] Music A3"),
      errors)
check("A0 brief authorizes no runtime mutation",
      brief.include?("Downloading model weights or repositories") &&
        brief.include?("Starting a model, API server, listener, container, service, or background job") &&
        brief.include?("authorizes no A1 installation or model pilot"),
      errors)
check("stale augmentation roadmap state is corrected",
      roadmap.include?("[x] A4 prepare human-approved isolated worktree") &&
        roadmap.include?("[x] A5 review exact augmentation candidate"),
      errors)
check("current milestone and state record the approved A1 gate",
      milestones.include?("Music A0 defined the topology") &&
        current.include?("A0 installed and ran nothing") &&
        current.include?("Music A1 is\ncomplete") &&
        current.include?("Music A2 is the next human-gated slice"),
      errors)
check("primary-source set covers candidates and host compatibility",
      %w[
        github.com/ace-step/ACE-Step-1.5
        github.com/ASLP-lab/DiffRhythm
        github.com/multimodal-art-projection/YuE
        github.com/facebookresearch/audiocraft
        rocm.docs.amd.com
      ].all? { |source| architecture.include?(source) },
      errors)
check("review artifact contains required completion sections",
      %w[implemented Files Commands Deterministic Local Known Memory lifecycle Risk checklist].all? { |word| review.downcase.include?(word.downcase) },
      errors)

if errors.empty?
  puts "Verification complete."
  puts "Multi-model and Music Studio A0 is candidate-complete for human review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
