# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "alpha_skill_plan_generator"
require_relative "alpha_behavior_scaffold"

module SoulCore
  class AlphaSkillGenerator
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def generate(proposal_path:)
      proposal_dir = normalize_proposal_path(proposal_path)
      metadata_path = File.join(proposal_dir, "metadata.json")

      return error("proposal folder not found", proposal_dir) unless Dir.exist?(proposal_dir)
      return error("metadata.json not found", proposal_dir) unless File.exist?(metadata_path)

      metadata = JSON.parse(File.read(metadata_path))
      behavior = AlphaBehaviorScaffold.new(metadata)
      alpha_dir = File.join(proposal_dir, "alpha")
      FileUtils.mkdir_p(alpha_dir)

      capability = metadata.fetch("capability", "unknown")
      title = metadata.fetch("title", "Alpha Skill")
      slug = metadata.fetch("id", slug(title))
      class_name = classify(slug)

      artifacts = {
        "readme" => File.join(alpha_dir, "README.md"),
        "implementation_plan" => File.join(alpha_dir, "implementation_plan.md"),
        "skill" => File.join(alpha_dir, "skill.rb"),
        "verifier" => File.join(alpha_dir, "verify-alpha.rb"),
        "test_cases" => File.join(alpha_dir, "test_cases.json"),
        "behavior_scaffold" => File.join(alpha_dir, "behavior_scaffold.json"),
        "promotion_checklist" => File.join(alpha_dir, "promotion_checklist.md"),
        "manifest" => File.join(alpha_dir, "alpha_manifest.json")
      }

      File.write(artifacts["implementation_plan"], AlphaSkillPlanGenerator.new.generate(metadata))
      File.write(artifacts["readme"], readme(metadata, capability, title, slug))
      File.write(artifacts["skill"], skill_rb(metadata, behavior, capability, class_name))
      File.write(artifacts["verifier"], verifier_rb(capability, class_name))
      File.write(artifacts["test_cases"], JSON.pretty_generate(test_cases(metadata, behavior, capability)))
      File.write(artifacts["behavior_scaffold"], JSON.pretty_generate(behavior.ruby_methods))
      File.write(artifacts["promotion_checklist"], promotion_checklist(metadata))
      File.write(artifacts["manifest"], JSON.pretty_generate(manifest(metadata, artifacts, proposal_dir, behavior)))
      FileUtils.chmod("+x", artifacts["verifier"])

      {
        "ok" => true,
        "assessment" => "alpha_skill_generation",
        "generated_at" => Time.now.iso8601,
        "proposal_path" => proposal_dir,
        "proposal_title" => title,
        "capability" => capability,
        "alpha_path" => alpha_dir,
        "artifacts" => artifacts,
        "registered" => false,
        "production_modified" => false,
        "requires_human_review" => true,
        "implementation_plan_generated" => true,
        "behavior_scaffold_generated" => true,
        "verification" => {
          "no_production_skills_modified" => true,
          "no_registry_modified" => true,
          "no_workflows_modified" => true,
          "proposal_local_only" => true
        }
      }
    rescue JSON::ParserError => e
      error("metadata.json parse failed: #{e.message}", proposal_path)
    end

    def render(report)
      return "Alpha skill generation failed: #{report['error']}\nPath: #{report['proposal_path']}" unless report["ok"]

      lines = []
      lines << "Soul Alpha Skill Artifacts"
      lines << "Generated: #{report['generated_at']}"
      lines << "Proposal: #{report['proposal_title']}"
      lines << "Capability: #{report['capability']}"
      lines << "Alpha path: #{report['alpha_path']}"
      lines << ""
      lines << "Artifacts"
      report.fetch("artifacts").each { |name, path| lines << "- #{name}: #{path}" }
      lines << ""
      lines << "Implementation plan generated: #{report['implementation_plan_generated']}"
      lines << "Behavior scaffold generated: #{report['behavior_scaffold_generated']}"
      lines << "Registered: #{report['registered']}"
      lines << "Production modified: #{report['production_modified']}"
      lines << "Requires human review: #{report['requires_human_review']}"
      lines.join("\n")
    end

    private

    def normalize_proposal_path(path)
      raw = path.to_s
      File.expand_path(raw.start_with?("/") ? raw : File.join(@root, raw))
    end

    def error(message, path)
      {"ok" => false, "assessment" => "alpha_skill_generation", "generated_at" => Time.now.iso8601, "proposal_path" => path, "error" => message, "registered" => false, "production_modified" => false}
    end

    def readme(_metadata, capability, title, slug)
      <<~MD
        # Alpha Skill: #{title}

        Capability: `#{capability}`

        Slug: `#{slug}`

        Status: `alpha`

        ## Purpose

        This alpha artifact was generated from an improvement proposal.

        It is intentionally proposal-local and is not registered with Soul.

        ## Implementation plan

        See:

        ```text
        implementation_plan.md
        ```

        ## Behavior scaffold

        See:

        ```text
        behavior_scaffold.json
        ```

        The behavior scaffold describes planned artifacts, behavior steps, and risks for the selected capability.

        ## Boundaries

        This alpha must not:

        - modify production skills
        - register itself
        - register workflows
        - install packages
        - download models
        - bypass human review

        ## Verify

        ```bash
        ruby verify-alpha.rb
        ```

        ## Promotion

        Promotion requires manual review and a future promotion workflow.
      MD
    end

    def skill_rb(metadata, behavior, capability, class_name)
      summary = metadata.fetch("summary", "Alpha skill scaffold.")
      methods = behavior.ruby_methods
      <<~RUBY
        # frozen_string_literal: true

        # Alpha skill scaffold generated by Soul.
        #
        # Capability: #{capability}
        #
        # This file is proposal-local and must not be registered automatically.

        require "json"
        require "time"

        module SoulCore
          module Alpha
            class #{class_name}
              def self.metadata
                {
                  "status" => "alpha",
                  "capability" => #{capability.inspect},
                  "summary" => #{summary.inspect},
                  "registered" => false,
                  "production_ready" => false,
                  "requires_human_review" => true,
                  "behavior_scaffold" => true
                }
              end

              def self.planned_artifacts
                #{methods.fetch("planned_artifacts").inspect}
              end

              def self.behavior_steps
                #{methods.fetch("behavior_steps").inspect}
              end

              def self.risks
                #{methods.fetch("risks").inspect}
              end

              def self.run(args: [])
                {
                  "ok" => true,
                  "status" => "alpha_behavior_scaffold",
                  "capability" => #{capability.inspect},
                  "args" => args,
                  "planned_artifacts" => planned_artifacts,
                  "behavior_steps" => behavior_steps,
                  "risks" => risks,
                  "message" => "Alpha behavior scaffold only. Implement behavior after human approval.",
                  "verification" => {
                    "production_modified" => false,
                    "registered" => false,
                    "behavior_scaffold" => true
                  },
                  "generated_at" => Time.now.iso8601
                }
              end
            end
          end
        end
      RUBY
    end

    def verifier_rb(capability, class_name)
      <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        require "json"

        root = File.expand_path(__dir__)
        skill_path = File.join(root, "skill.rb")
        manifest_path = File.join(root, "alpha_manifest.json")
        test_cases_path = File.join(root, "test_cases.json")
        checklist_path = File.join(root, "promotion_checklist.md")
        plan_path = File.join(root, "implementation_plan.md")
        behavior_path = File.join(root, "behavior_scaffold.json")

        errors = []

        puts "alpha skill verification: #{capability}"

        [skill_path, manifest_path, test_cases_path, checklist_path, plan_path, behavior_path].each do |path|
          ok = File.exist?(path)
          puts "- \#{File.basename(path)} exists: \#{ok ? 'ok' : 'missing'}"
          errors << "\#{path} missing" unless ok
        end

        syntax_ok = system("ruby", "-c", skill_path, out: File::NULL, err: File::NULL)
        puts "- skill.rb syntax: \#{syntax_ok ? 'ok' : 'missing'}"
        errors << "skill.rb syntax invalid" unless syntax_ok

        plan_ok = File.read(plan_path).include?("Implementation Plan") && File.read(plan_path).include?("Prohibited behavior")
        puts "- implementation plan shape: \#{plan_ok ? 'ok' : 'missing'}"
        errors << "implementation plan invalid" unless plan_ok

        behavior = JSON.parse(File.read(behavior_path)) rescue nil
        behavior_ok =
          behavior &&
          behavior["planned_artifacts"].is_a?(Array) &&
          behavior["behavior_steps"].is_a?(Array) &&
          behavior["risks"].is_a?(Array) &&
          behavior["behavior_steps"].any?
        puts "- behavior scaffold shape: \#{behavior_ok ? 'ok' : 'missing'}"
        errors << "behavior scaffold invalid" unless behavior_ok

        require skill_path

        klass = SoulCore::Alpha::#{class_name}
        metadata = klass.metadata
        result = klass.run(args: ["--alpha-verify"])

        metadata_ok =
          metadata["status"] == "alpha" &&
          metadata["registered"] == false &&
          metadata["production_ready"] == false &&
          metadata["requires_human_review"] == true &&
          metadata["behavior_scaffold"] == true
        puts "- alpha metadata boundaries: \#{metadata_ok ? 'ok' : 'missing'}"
        errors << "alpha metadata boundaries failed" unless metadata_ok

        result_ok =
          result["ok"] == true &&
          result["status"] == "alpha_behavior_scaffold" &&
          result["behavior_steps"].is_a?(Array) &&
          result.dig("verification", "production_modified") == false &&
          result.dig("verification", "registered") == false &&
          result.dig("verification", "behavior_scaffold") == true
        puts "- alpha run boundaries: \#{result_ok ? 'ok' : 'missing'}"
        errors << "alpha run boundaries failed" unless result_ok

        manifest = JSON.parse(File.read(manifest_path)) rescue nil
        manifest_ok =
          manifest &&
          manifest["registered"] == false &&
          manifest["production_modified"] == false &&
          manifest["requires_human_review"] == true &&
          manifest["behavior_scaffold_generated"] == true &&
          manifest.dig("artifacts", "behavior_scaffold")
        puts "- manifest boundaries: \#{manifest_ok ? 'ok' : 'missing'}"
        errors << "manifest boundaries failed" unless manifest_ok

        if errors.empty?
          puts "Verification complete."
          exit 0
        else
          warn "Verification failed:"
          errors.each { |error| warn "- \#{error}" }
          exit 1
        end
      RUBY
    end

    def test_cases(metadata, behavior, capability)
      {"status" => "alpha", "capability" => capability, "proposal_title" => metadata["title"], "cases" => [{"name" => "alpha metadata", "expected" => {"registered" => false, "production_ready" => false, "requires_human_review" => true, "behavior_scaffold" => true}}, {"name" => "implementation plan exists", "expected" => {"file" => "implementation_plan.md"}}, {"name" => "behavior scaffold exists", "expected" => {"file" => "behavior_scaffold.json", "behavior_steps_minimum" => 1}}, {"name" => "planned artifacts", "expected" => {"items" => behavior.planned_artifacts}}, {"name" => "alpha behavior scaffold run", "expected" => {"production_modified" => false, "registered" => false, "status" => "alpha_behavior_scaffold"}}]}
    end

    def promotion_checklist(metadata)
      <<~MD
        # Promotion Checklist

        Proposal: #{metadata["title"]}

        Capability: `#{metadata["capability"]}`

        ## Required before beta

        - [ ] Human reviewed proposal.
        - [ ] Human approved implementation direction.
        - [ ] Implementation plan reviewed.
        - [ ] Behavior scaffold reviewed.
        - [ ] Alpha verifier passes.
        - [ ] Behavior is implemented, not scaffold-only.
        - [ ] Boundaries are documented.
        - [ ] Failure modes are documented.
        - [ ] No production files are modified outside promotion workflow.
        - [ ] Skill registry changes are explicit.
        - [ ] Workflow registry changes are explicit when needed.
        - [ ] Rollback path is documented.

        ## Required before production

        - [ ] Beta usage tested.
        - [ ] Contract validation passes.
        - [ ] Docs are added under the correct docs path.
        - [ ] No secrets are printed or persisted.
        - [ ] No destructive action occurs without confirmation.
      MD
    end

    def manifest(metadata, artifacts, proposal_dir, _behavior)
      {"status" => "alpha", "generated_at" => Time.now.iso8601, "proposal_path" => proposal_dir, "proposal_title" => metadata["title"], "capability" => metadata["capability"], "artifacts" => artifacts.transform_values { |path| path.sub(@root + "/", "") }, "registered" => false, "production_modified" => false, "requires_human_review" => true, "implementation_plan_generated" => true, "behavior_scaffold_generated" => true}
    end

    def slug(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
    end

    def classify(value)
      value.to_s.split(/[^a-zA-Z0-9]/).reject(&:empty?).map(&:capitalize).join
    end
  end
end
