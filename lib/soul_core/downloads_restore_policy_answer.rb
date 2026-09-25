# frozen_string_literal: true

module SoulCore
  # Explains the fixed Downloads restore contract without asking a model to
  # infer whether confirmation can waive a filesystem refusal.
  class DownloadsRestorePolicyAnswer
    RESTORE_TOPIC = /\b(?:restor(?:e|es|ing|ation)|recover(?:y|ing)?)\b/i
    DOWNLOADS_TOPIC = /\b(?:downloads?|cleanup)\b/i
    COLLISION_TOPIC = /\b(?:original\s+path|destination|already\s+exists|existing\s+(?:file|path)|overwrite|rename)\b/i
    QUESTION = /\b(?:what|how|which|why|does|do|is|are|can|could|would|will|explain|describe|tell\s+me|safeguards)\b/i
    COMMAND = /\b(?:go\s+ahead|do\s+it|execute|run\s+the\s+restore)\b|\A\s*(?:(?:hey\s+)?soul[,!]?\s*)?(?:(?:please\s+)?(?:can|could|would|will)\s+you\s+(?:please\s+)?|please\s+)?(?:restore|recover|move)\b/i

    def needs_context?(message)
      text = message.to_s.strip
      text.match?(QUESTION) && !text.match?(COMMAND) && text.match?(COLLISION_TOPIC) && !restore_topic?(text)
    end

    def answer(message:, previous_user_message: nil)
      text = message.to_s.strip
      return nil unless text.match?(QUESTION) && !text.match?(COMMAND)

      current_topic = restore_topic?(text)
      previous_topic = restore_topic?(previous_user_message.to_s)
      return nil unless current_topic || (previous_topic && text.match?(COLLISION_TOPIC))

      if text.match?(COLLISION_TOPIC)
        "For Soul's Downloads cleanup restore, an existing original path blocks the restore before any file is moved. Soul refuses to overwrite it; confirmation and --execute cannot override that block. Soul does not automatically rename the Trash item or choose another destination."
      else
        "Soul can restore items recorded in its most recent successful Downloads cleanup. It shows the candidates, asks for a selection, and requires final confirmation before execution. An existing original path blocks the restore even after confirmation; Soul does not overwrite it or automatically rename the Trash item."
      end
    end

    private

    def restore_topic?(text)
      text.match?(RESTORE_TOPIC) && text.match?(DOWNLOADS_TOPIC)
    end
  end
end
