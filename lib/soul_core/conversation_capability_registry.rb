# frozen_string_literal: true

require_relative "conversation_request_shape"

module SoulCore
  class ConversationCapabilityRegistry
    VALID_STATUSES = %w[available conditional unavailable].freeze

    Capability = Struct.new(
      :id,
      :label,
      :domain,
      :status,
      :risk_class,
      :tool_id,
      :scope,
      :summary,
      :limitations,
      :patterns,
      keyword_init: true
    ) do
      def available?
        status == "available"
      end

      def conditional?
        status == "conditional"
      end

      def unavailable?
        status == "unavailable"
      end

      def matches?(message)
        Array(patterns).any? { |pattern| message.match?(pattern) }
      end

      def to_h
        {
          "id" => id,
          "label" => label,
          "domain" => domain,
          "status" => status,
          "risk_class" => risk_class,
          "tool_id" => tool_id,
          "scope" => scope,
          "summary" => summary,
          "limitations" => Array(limitations)
        }.reject { |_key, value| value.nil? }
      end
    end

    Resolution = Struct.new(
      :matched,
      :kind,
      :reason,
      :capability,
      keyword_init: true
    ) do
      def matched?
        matched == true
      end

      def catalog?
        kind == "catalog"
      end

      def gap?
        kind == "capability_gap"
      end

      def info?
        kind == "capability_info"
      end

      def available_action?
        kind == "available_action"
      end

      def to_h
        {
          "matched" => matched?,
          "kind" => kind.to_s,
          "reason" => reason.to_s,
          "capability" => capability&.to_h
        }.reject { |_key, value| value.nil? }
      end
    end

    CATALOG_PATTERNS = [
      /\bwhat (?:host|system|machine|computer) (?:checks|diagnostics|capabilities) (?:can|do) you (?:perform|run|support|have)\b/i,
      /\bwhat can you check (?:on|about) (?:this|my|the) (?:host|system|machine|computer)\b/i,
      /\b(?:list|show|describe) (?:the )?(?:host|system) (?:checks|diagnostics|capabilities)\b/i,
      /\bwhich (?:host|system) (?:checks|diagnostics) are (?:available|supported|registered)\b/i,
      /\bwhat (?:is|isn't|is not) collected by (?:the )?host (?:check|assessment)\b/i
    ].freeze

    SUPPORT_QUESTION_PATTERNS = [
      /\bdo you support\b/i,
      /\bis .{0,80}\b(?:supported|available|registered)\b/i,
      /\bare you able to\b/i,
      /\bdo you have (?:a|an|the)?\s*(?:check|collector|capability)\b/i
    ].freeze

    DEFINITIONS = [
      Capability.new(
        id: "host.system_status",
        label: "Bounded host system status",
        domain: "host",
        status: "available",
        risk_class: "read_only",
        tool_id: "host.system_status",
        scope: "Bounded read-only Linux host environment assessment",
        summary: "Collects host identity, operating system, kernel, uptime, load, memory, mounted filesystems, physical block devices, network-link state, and a systemd summary.",
        limitations: [
          "The collector reports only explicitly collected values.",
          "Deeper device, security, scheduling, and application-health categories remain separate capabilities."
        ],
        patterns: [
          /\b(?:host|system|machine|computer) status\b/i,
          /\bhost environment assessment\b/i,
          /\bbounded host assessment\b/i
        ]
      ),
      Capability.new(
        id: "host.linux_mdraid",
        label: "Linux MD RAID summary",
        domain: "host",
        status: "conditional",
        risk_class: "read_only",
        tool_id: "host.system_status",
        scope: "Linux MD RAID state exposed through /proc/mdstat",
        summary: "The bounded host collector can report Linux MD RAID state when /proc/mdstat is readable and parseable.",
        limitations: [
          "Hardware RAID controller state is a different capability.",
          "An unavailable /proc/mdstat source is reported explicitly rather than inferred."
        ],
        patterns: [
          /\blinux md(?: raid)?\b/i,
          /\bmdraid\b/i,
          /\/proc\/mdstat/i
        ]
      ),
      Capability.new(
        id: "host.smart_health",
        label: "SMART device health",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Per-device SMART health and attributes",
        summary: "No bounded SMART collector is registered yet.",
        limitations: [
          "Soul does not infer drive health from model output or ordinary filesystem statistics.",
          "Enabling this requires a separately declared read-only collector with device and privilege boundaries."
        ],
        patterns: [
          /\bsmart(?:ctl)? (?:device )?health\b/i,
          /\bsmart attributes?\b/i,
          /\bdrive health\b/i,
          /\bdisk health\b/i
        ]
      ),
      Capability.new(
        id: "host.storage_temperature",
        label: "Storage-device temperatures",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Temperature telemetry for storage devices",
        summary: "No bounded storage-temperature collector is registered yet.",
        limitations: [
          "Temperature support varies by device type, transport, kernel interface, and permissions.",
          "No healthy-temperature conclusion is inferred when telemetry is absent."
        ],
        patterns: [
          /\b(?:drive|disk|ssd|nvme|storage(?:-device)?) temperatures?\b/i,
          /\bstorage thermal\b/i
        ]
      ),
      Capability.new(
        id: "host.hardware_raid",
        label: "Hardware RAID controller state",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Vendor-controller and logical-array health",
        summary: "No hardware RAID controller collector is registered.",
        limitations: [
          "Linux MD RAID state does not establish hardware RAID health.",
          "Vendor-specific tools and privilege rules must be declared before collection."
        ],
        patterns: [
          /\bhardware raid\b/i,
          /\braid controller\b/i,
          /\blogical (?:drive|array) health\b/i
        ]
      ),
      Capability.new(
        id: "host.zfs_pool_health",
        label: "ZFS pool health",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "ZFS pool and vdev state",
        summary: "No bounded ZFS pool-health collector is registered.",
        limitations: [
          "Filesystem presence alone does not establish pool health.",
          "A future collector must preserve pool, vdev, error, and scrub provenance."
        ],
        patterns: [
          /\bzfs pool health\b/i,
          /\bzpool (?:status|health)\b/i,
          /\bzfs health\b/i
        ]
      ),
      Capability.new(
        id: "host.firewall_policy",
        label: "Firewall policy",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Active firewall framework, policy, and rule summary",
        summary: "No bounded firewall-policy collector is registered.",
        limitations: [
          "Interface state and external reachability do not establish firewall policy.",
          "A future collector must distinguish nftables, iptables, firewalld, and other policy sources."
        ],
        patterns: [
          /\bfirewall policy\b/i,
          /\bfirewall rules?\b/i,
          /\b(?:nftables|iptables|firewalld) (?:policy|rules?|status)\b/i
        ]
      ),
      Capability.new(
        id: "host.authentication_logs",
        label: "Authentication logs",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Bounded authentication-event review",
        summary: "No authentication-log collector is registered.",
        limitations: [
          "Authentication logs may contain sensitive usernames, addresses, and event details.",
          "Collection requires explicit source, redaction, retention, and time-window boundaries."
        ],
        patterns: [
          /\bauthentication logs?\b/i,
          /\bauth logs?\b/i,
          /\bfailed logins?\b/i,
          /\bssh login history\b/i
        ]
      ),
      Capability.new(
        id: "host.scheduled_jobs",
        label: "Scheduled jobs",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Cron, systemd timer, and related scheduler inventory",
        summary: "No bounded scheduled-job collector is registered.",
        limitations: [
          "A future collector must define system and user scope.",
          "Command contents and environment values require redaction rules."
        ],
        patterns: [
          /\bscheduled jobs?\b/i,
          /\bcron jobs?\b/i,
          /\bcrontab\b/i,
          /\bsystemd timers?\b/i
        ]
      ),
      Capability.new(
        id: "host.package_updates",
        label: "Package update state",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Available operating-system package updates",
        summary: "No package-update collector is registered in the conversation runtime.",
        limitations: [
          "Package-manager refresh behavior and network access must be bounded.",
          "The capability must not install or upgrade packages."
        ],
        patterns: [
          /\bpackage update state\b/i,
          /\bavailable (?:package )?updates\b/i,
          /\bsystem updates?\b/i,
          /\bpackages? (?:need|requiring) updates?\b/i
        ]
      ),
      Capability.new(
        id: "host.external_network_reachability",
        label: "External network reachability",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Bounded outbound DNS and network reachability checks",
        summary: "No external-reachability collector is registered.",
        limitations: [
          "Network-interface link state does not establish Internet or service reachability.",
          "Future probes require explicit destinations, protocols, timeouts, and privacy boundaries."
        ],
        patterns: [
          /\bexternal network reachability\b/i,
          /\binternet (?:access|connectivity|reachability)\b/i,
          /\bcan (?:the )?(?:host|system|machine) reach\b/i,
          /\bdns reachability\b/i
        ]
      ),
      Capability.new(
        id: "host.application_process_health",
        label: "Application process health",
        domain: "host",
        status: "unavailable",
        risk_class: "read_only",
        scope: "Application-specific process and service health beyond the systemd summary",
        summary: "No generic application-process health collector is registered.",
        limitations: [
          "A running process alone does not establish application health.",
          "Future checks should be application-specific and declare their evidence and timeout contracts."
        ],
        patterns: [
          /\bapplication process health\b/i,
          /\bprocess health\b/i,
          /\bapplication health\b/i,
          /\bapp health\b/i
        ]
      )
    ].freeze

    def initialize(definitions: DEFINITIONS)
      @definitions = Array(definitions).freeze
      validate_definitions!
    end

    def definitions
      @definitions
    end

    def find(capability_id)
      definitions.find { |capability| capability.id == capability_id.to_s }
    end

    def resolve(message)
      text = message.to_s.strip
      return unmatched("the capability request is empty") if text.empty?
      return unmatched("the capability was mentioned without an explicit request") unless ConversationRequestShape.new.request?(text)

      if CATALOG_PATTERNS.any? { |pattern| text.match?(pattern) }
        return Resolution.new(
          matched: true,
          kind: "catalog",
          reason: "the message requests the declared host capability catalog",
          capability: nil
        )
      end

      capability = definitions.find { |definition| definition.matches?(text) }
      return unmatched("the message does not match a declared capability") unless capability

      kind = if support_question?(text)
               "capability_info"
             elsif capability.unavailable?
               "capability_gap"
             else
               "available_action"
             end

      Resolution.new(
        matched: true,
        kind: kind,
        reason: resolution_reason(capability, kind),
        capability: capability
      )
    end

    def resolve_id(capability_id, kind: nil)
      capability = find(capability_id)
      return unmatched("the requested capability is not registered") unless capability

      resolved_kind = kind.to_s
      resolved_kind = capability.unavailable? ? "capability_gap" : "capability_info" if resolved_kind.empty?

      Resolution.new(
        matched: true,
        kind: resolved_kind,
        reason: resolution_reason(capability, resolved_kind),
        capability: capability
      )
    end

    def summary(domain: nil)
      selected = filtered_definitions(domain)
      {
        "total" => selected.length,
        "available" => selected.count(&:available?),
        "conditional" => selected.count(&:conditional?),
        "unavailable" => selected.count(&:unavailable?)
      }
    end

    def render_catalog(domain: "host")
      selected = filtered_definitions(domain)
      lines = ["Declared #{domain} capabilities", ""]

      append_group(lines, "Available now", selected.select(&:available?))
      append_group(lines, "Conditionally available", selected.select(&:conditional?))
      append_group(lines, "Not currently registered", selected.select(&:unavailable?))

      lines << ""
      lines << "Unavailable categories are explicit boundaries; Soul does not replace them with model inference."
      lines.join("\n")
    end

    def render(resolution)
      return "The requested capability is not registered." unless resolution&.matched?
      return render_catalog if resolution.catalog?

      capability = resolution.capability
      lines = [capability.label, "Capability ID: #{capability.id}"]
      lines << "Status: #{capability.status}"
      lines << "Risk class: #{capability.risk_class}"
      lines << "Tool: #{capability.tool_id}" unless capability.tool_id.to_s.empty?
      lines << "Scope: #{capability.scope}"
      if capability.unavailable? && capability.domain == "host"
        lines << "The bounded host assessment does not collect that deeper host category."
      end
      lines << capability.summary.to_s

      limitations = Array(capability.limitations)
      unless limitations.empty?
        lines << "Boundaries:"
        limitations.each { |item| lines << "- #{item}" }
      end

      if capability.unavailable?
        lines << "No model-generated substitute will be treated as collected evidence."
      elsif capability.conditional?
        lines << "The result must state explicitly when its underlying source is unavailable."
      end

      lines.join("\n")
    end

    private

    def unmatched(reason)
      Resolution.new(
        matched: false,
        kind: "unmatched",
        reason: reason,
        capability: nil
      )
    end

    def support_question?(text)
      SUPPORT_QUESTION_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def resolution_reason(capability, kind)
      case kind
      when "capability_gap"
        "#{capability.id} is declared but unavailable"
      when "capability_info"
        "the message asks whether #{capability.id} is supported"
      else
        "#{capability.id} is available through its registered deterministic tool"
      end
    end

    def filtered_definitions(domain)
      value = domain.to_s
      return definitions if value.empty?

      definitions.select { |capability| capability.domain == value }
    end

    def append_group(lines, heading, capabilities)
      return if capabilities.empty?

      lines << heading + ":"
      capabilities.each do |capability|
        tool = capability.tool_id.to_s.empty? ? "" : " via #{capability.tool_id}"
        lines << "- #{capability.label} (#{capability.id}) — #{capability.status}#{tool}."
      end
      lines << ""
    end

    def validate_definitions!
      ids = definitions.map(&:id)
      duplicates = ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
      raise ArgumentError, "Duplicate capability IDs: #{duplicates.join(', ')}" unless duplicates.empty?

      invalid = definitions.reject do |capability|
        !capability.id.to_s.empty? &&
          !capability.label.to_s.empty? &&
          VALID_STATUSES.include?(capability.status.to_s) &&
          !capability.risk_class.to_s.empty? &&
          !Array(capability.patterns).empty?
      end
      return if invalid.empty?

      raise ArgumentError, "Invalid capability definitions: #{invalid.map(&:id).join(', ')}"
    end
  end
end
