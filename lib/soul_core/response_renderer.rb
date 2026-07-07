# frozen_string_literal: true

module SoulCore
  class ResponseRenderer
    def render_weather_needs_location(state)
      lines = []
      lines << "I can run the weather report, but I need a location."
      lines << ""
      lines << "Try:"
      lines << ""
      lines << '- `ruby bin/soul do "what is the weather today in Syracuse, NY"`'
      lines << ""
      lines << "Or set a default in `.env`:"
      lines << ""
      lines << "- `SOUL_WEATHER_LOCATION=Syracuse, NY`"
      lines.join("\n")
    end

    def render_weather_brief(state, report)
      current = report["current"] || {}
      air = current["air_quality"] || {}
      lines = []

      lines << "Workflow: #{state.fetch('workflow')}"
      lines << "Status: #{state.fetch('status')}"
      lines << "Weather log: #{state.dig('verification', 'brief_report_log')}"
      lines << "Workflow state: #{state.fetch('workflow_path')}" if state["workflow_path"]
      lines << ""
      lines << "# Weather Today"
      lines << ""
      lines << "- Location: #{current['location'] || report.dig('resolved_location', 'name')}"
      lines << "- Condition: #{current['condition'] || 'unavailable'}"
      lines << "- Temperature: #{format_temperature(current)}"
      lines << "- Humidity: #{current['humidity_percent'] || 'unavailable'}%"
      lines << "- Air quality: #{format_air_quality(air)}"
      lines << ""
      lines << report["summary"].to_s unless report["summary"].to_s.strip.empty?
      lines << ""
      lines << "Would you like the detailed report with a 3-day outlook and notable forecast signals?"
      lines << ""
      lines << '- `ruby bin/soul respond "yes"`'
      lines << '- `ruby bin/soul respond "no"`'
      lines.join("\n")
    end

    def render_weather_complete_without_detail(state)
      lines = []
      lines << "Weather workflow complete."
      lines << ""
      lines << "- Detailed report requested: no"
      lines << "- Final state: complete"
      lines << ""
      lines << "Next: `ruby bin/soul reflect last` if this task should produce a reflection candidate."
      lines.join("\n")
    end

    def render_weather_detailed(state, report)
      current = report["current"] || {}
      detailed = report["detailed_report"] || {}
      outlook = detailed["outlook_days"] || []
      signals = detailed["notable_forecast_signals"] || []

      lines = []
      lines << "Weather workflow complete."
      lines << ""
      lines << "# Current Conditions"
      lines << ""
      lines << "- Location: #{current['location'] || report.dig('resolved_location', 'name')}"
      lines << "- Condition: #{current['condition'] || 'unavailable'}"
      lines << "- Temperature: #{format_temperature(current)}"
      lines << "- Humidity: #{current['humidity_percent'] || 'unavailable'}%"
      lines << "- Air quality: #{format_air_quality(current['air_quality'] || {})}"
      lines << ""

      unless outlook.empty?
        lines << "# 3-Day Outlook"
        lines << ""
        outlook.each do |day|
          lines << "- #{day['date']}: #{day['condition']}; high #{format_number(day['high'])}, low #{format_number(day['low'])}; precip #{day['precipitation_probability_percent'] || 'unavailable'}%; max wind #{format_number(day['max_wind_speed'])}"
        end
        lines << ""
      end

      lines << "# Notable Forecast Signals"
      lines << ""
      signals.each { |signal| lines << "- #{signal}" }
      lines << ""
      lines << "- Final state: complete"
      lines << ""
      lines << "Next: `ruby bin/soul reflect last` if this task should produce a reflection candidate."
      lines.join("\n")
    end

    def render_plan(state, plan)
      lines = []
      candidates = state.fetch("candidates", [])
      summary = state.fetch("summary", {})

      lines << "Workflow: #{state.fetch('workflow')}"
      lines << "Status: #{state.fetch('status')}"
      lines << "Plan log: #{state.dig('verification', 'plan_log')}"
      lines << "Workflow state: #{state.fetch('workflow_path')}" if state["workflow_path"]
      lines << ""
      lines << "# Cleanup Summary"
      lines << ""
      lines << "- Target: `#{state.dig('parameters', 'target_path')}`"
      lines << "- Older than: #{state.dig('parameters', 'older_than_days')} days"
      lines << "- Recursive scan: no"
      lines << "- Entries inspected: #{summary['total_entries_inspected'] || 0}"
      lines << "- Cleanup candidates: #{summary['cleanup_candidate_count'] || 0}"
      lines << "- Candidate files: #{summary['cleanup_candidate_file_count'] || 0}"
      lines << "- Candidate folders: #{summary['cleanup_candidate_directory_count'] || 0}"
      lines << "- Protected entries: #{summary['protected_count'] || 0}"
      lines << ""

      if candidates.empty?
        lines << "No cleanup candidates were found. Nothing will be moved."
        protected = plan.dig("proposed_actions", "keep_protected") || []
        unless protected.empty?
          lines << ""
          lines << "Protected:"
          protected.each { |item| lines << "- `#{item['path']}` - matched #{Array(item['matched_terms']).join(', ')}" }
        end
        return lines.join("\n")
      end

      folders = candidates.select { |candidate| candidate["type"] == "directory" }
      files = candidates.select { |candidate| candidate["type"] == "file" }

      unless folders.empty?
        lines << "## Folder Candidates"
        lines << ""
        folders.each do |candidate|
          ds = candidate["directory_summary"]
          extra = ds ? " - top-level contents: #{ds['top_level_entry_count']} entries" : ""
          lines << "- #{candidate['id']}: `#{candidate['name']}` (#{candidate['age_days']} days old#{extra})"
        end
        lines << ""
      end

      unless files.empty?
        lines << "## File Candidates"
        lines << ""
        files.each do |candidate|
          lines << "- #{candidate['id']}: `#{candidate['name']}` (#{candidate['size_human']}, #{candidate['age_days']} days old)"
        end
        lines << ""
      end

      lines << "## Options"
      lines << ""
      lines << '- `ruby bin/soul respond "move all"`'
      lines << '- `ruby bin/soul respond "move all except F1"`'
      lines << '- `ruby bin/soul respond "only move F1 and D1"`'
      lines << '- `ruby bin/soul respond "cancel"`'
      lines.join("\n")
    end

    def render_selection(state)
      selected = state.fetch("selected_candidates", [])
      excluded = state.fetch("excluded_candidates", [])
      lines = []

      lines << "Selection staged."
      lines << ""

      if selected.empty?
        lines << "No candidates selected for Trash."
      else
        lines << "Will move to Trash:"
        selected.each { |candidate| lines << "- #{candidate['id']}: `#{candidate['name']}` (#{candidate['type']})" }
      end

      unless excluded.empty?
        lines << ""
        lines << "Will keep:"
        excluded.each { |candidate| lines << "- #{candidate['id']}: `#{candidate['name']}` (#{candidate['type']})" }
      end

      lines << ""
      lines << "Ready to move the selected items to Trash?"
      lines << ""
      lines << '- `ruby bin/soul respond "yeah, do it"`'
      lines << '- `ruby bin/soul respond "cancel"`'
      lines.join("\n")
    end

    def render_restore_plan(state, restore_result)
      lines = []
      candidates = state.fetch("candidates", [])

      lines << "Workflow: #{state.fetch('workflow')}"
      lines << "Status: #{state.fetch('status')}"
      lines << "Source move log: #{state.dig('verification', 'source_move_log')}"
      lines << "Workflow state: #{state.fetch('workflow_path')}" if state["workflow_path"]
      lines << ""
      lines << "# Restore Last Cleanup"
      lines << ""

      if candidates.empty?
        lines << (restore_result["recommendation"] || "No restore candidates were found.")
        Array(restore_result["warnings"]).each { |warning| lines << "- Warning: #{warning}" }
        Array(restore_result["errors"]).each { |error| lines << "- Error: #{error}" }
        return lines.join("\n")
      end

      lines << "Restore candidates from the latest successful Downloads cleanup:"
      lines << ""

      candidates.each do |candidate|
        status = candidate["valid"] ? "ready" : "blocked"
        lines << "- #{candidate['id']}: `#{candidate['name']}` (#{candidate['type']}, #{status})"
        Array(candidate["errors"]).each { |error| lines << "  - #{error}" }
      end

      lines << ""
      lines << "## Options"
      lines << ""
      lines << '- `ruby bin/soul respond "restore all"`'
      lines << '- `ruby bin/soul respond "restore all except F1"`'
      lines << '- `ruby bin/soul respond "only restore F1 and D1"`'
      lines << '- `ruby bin/soul respond "cancel"`'
      lines.join("\n")
    end

    def render_restore_selection(state)
      selected = state.fetch("selected_candidates", [])
      excluded = state.fetch("excluded_candidates", [])
      lines = []

      lines << "Restore selection staged."
      lines << ""

      if selected.empty?
        lines << "No candidates selected for restore."
      else
        lines << "Will restore from Trash:"
        selected.each { |candidate| lines << "- #{candidate['id']}: `#{candidate['name']}` (#{candidate['type']})" }
      end

      unless excluded.empty?
        lines << ""
        lines << "Will leave in Trash:"
        excluded.each { |candidate| lines << "- #{candidate['id']}: `#{candidate['name']}` (#{candidate['type']})" }
      end

      lines << ""
      lines << "Ready to restore the selected items from Trash?"
      lines << ""
      lines << '- `ruby bin/soul respond "yeah, do it"`'
      lines << '- `ruby bin/soul respond "cancel"`'
      lines.join("\n")
    end

    def render_execution(result)
      data = result[:json] || {}
      verification = data["verification"] || {}
      moved = data["moved"] || []
      failed = data["failed"] || []
      lines = []

      lines << (data["recommendation"] || "Move-to-Trash workflow completed.")
      lines << ""
      lines << "- Outcome: #{data['outcome']}"
      lines << "- Moved files: #{verification['moved_files'] || 0}"
      lines << "- Moved folders: #{verification['moved_directories'] || 0}"
      lines << "- Permanent deletions: #{verification['deleted_files'] || 0}"
      lines << ""

      unless moved.empty?
        lines << "Moved to Trash:"
        moved.each { |item| lines << "- `#{item['path']}`" }
        lines << ""
      end

      unless failed.empty?
        lines << "Failed:"
        failed.each { |item| lines << "- `#{item['path']}`" }
        lines << ""
      end

      lines << "Restore is possible from Trash if needed."
      lines << "Next: `ruby bin/soul reflect last` if this task should produce a reflection candidate."
      lines.join("\n")
    end

    def render_restore_execution(result)
      data = result[:json] || {}
      verification = data["verification"] || {}
      restored = data["restored"] || []
      failed = data["failed"] || []
      lines = []

      lines << (data["recommendation"] || "Restore workflow completed.")
      lines << ""
      lines << "- Outcome: #{data['outcome']}"
      lines << "- Restored files: #{verification['restored_files'] || 0}"
      lines << "- Restored folders: #{verification['restored_directories'] || 0}"
      lines << "- Permanent deletions: #{verification['deleted_files'] || 0}"
      lines << ""

      unless restored.empty?
        lines << "Restored from Trash:"
        restored.each { |item| lines << "- `#{item['path']}`" }
        lines << ""
      end

      unless failed.empty?
        lines << "Failed:"
        failed.each { |item| lines << "- `#{item['path']}`" }
        lines << ""
      end

      lines << "Next: `ruby bin/soul reflect last` if this restore task should produce a reflection candidate."
      lines.join("\n")
    end

    private

    def format_temperature(current)
      temp = current["temperature"]
      return "unavailable" if temp.nil?

      unit = current["temperature_unit"] == "celsius" ? "°C" : "°F"
      "#{temp.round}#{unit}"
    end

    def format_air_quality(air)
      aqi = air["us_aqi"]
      category = air["category"] || "Unavailable"

      if aqi
        "#{aqi.round} US AQI (#{category})"
      else
        category
      end
    end

    def format_number(value)
      return "unavailable" if value.nil?

      value.is_a?(Numeric) ? value.round.to_s : value.to_s
    end
  end
end
