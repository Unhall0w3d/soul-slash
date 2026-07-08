# frozen_string_literal: true

# Compatibility require for older application boot paths.
#
# YouTube workflow behavior now lives in:
#
#   SoulCore::Workflows::YouTubePlayHandler
#
# YouTube intent matching now loads through:
#
#   SoulCore::WorkflowIntentHandlerDispatchPatch
#
# This file should remain tiny until the app boot path no longer requires it.

require_relative "workflow_intent_handler_dispatch"
