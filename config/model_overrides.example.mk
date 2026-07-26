# Copy this file to ../Makefile.local and edit that ignored local copy.
#
# Command-line assignments take precedence:
#   make setup-llamacpp LLAMACPP_MODEL_FILE=Exact.gguf LLAMACPP_MODEL_URL=https://...
#
# Chat defaults
LLAMACPP_MODEL_FILE = Qwen3-8B-Q4_K_M.gguf
LLAMACPP_MODEL_URL = https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true
OLLAMA_MODEL = gemma4:12b-it-q4_K_M
GEMMA_SOURCE_MODEL = $(OLLAMA_MODEL)
GEMMA_API_MODEL = soul-local-chat
GEMMA_PORT = 8082

# Creative model substitutions require a complete reviewed manifest. A manifest
# binds repository, revision, exact case-sensitive filename, byte size, SHA-256,
# runtime parameters, and supported bounds; a loose filename is not sufficient.
# MUSIC_VULKAN_MANIFEST = /absolute/path/to/custom-music-models.json
# VISUAL_MODEL_MANIFEST = /absolute/path/to/custom-still-models.json
# VISUAL_MOTION_MANIFEST = /absolute/path/to/custom-image-motion-models.json
# VISUAL_NATIVE_MANIFEST = /absolute/path/to/custom-native-video-models.json
# MUSIC_TRANSCRIPTION_MANIFEST = /absolute/path/to/custom-transcription-models.json
# VOICE_TRANSCRIPTION_ROOT = /absolute/path/to/shared-transcription-runtime
# VOICE_TRANSCRIPTION_MANIFEST = /absolute/path/to/custom-transcription-models.json
# VOICE_TRANSCRIPTION_MODEL = exact-model-filename-from-manifest.bin
# VOICE_SYNTHESIS_ROOT = /absolute/path/to/user-local/voice/runtime
# VOICE_SYNTHESIS_MANIFEST = /absolute/path/to/custom-voice-synthesis-models.json
# VOICE_SYNTHESIS_REQUIREMENTS = /absolute/path/to/pinned-requirements.txt
# SOUL_VOICE_SYNTHESIS_VOICE belongs in .env and must be F1-F5 or M1-M5.
# VOICE_EXPRESSIVE_ROOT = /absolute/path/to/user-local/voice/expressive
# VOICE_EXPRESSIVE_MANIFEST = /absolute/path/to/custom-expressive-voice-models.json
# VOICE_EXPRESSIVE_REQUIREMENTS = /absolute/path/to/pinned-expressive-requirements.txt
# VOICE_PRESENCE_ROOT = /absolute/path/to/user-local/voice/presence
# VOICE_PRESENCE_MANIFEST = /absolute/path/to/custom-wake-models.json
# VOICE_PRESENCE_REQUIREMENTS = /absolute/path/to/pinned-wake-requirements.txt
# VOICE_PRESENCE_SOURCE = exact-pipewire-source-node
# MUSIC_TRANSCRIPTION_MODEL = exact-model-filename.bin
