# frozen_string_literal: true

module SoulCore
  class AlphaSkillPlanGenerator
    def generate(metadata)
      capability = metadata.fetch("capability", "unknown")
      title = metadata.fetch("title", "Untitled alpha skill")
      summary = metadata.fetch("summary", "No summary provided.")
      first_steps = Array(metadata["first_steps"])
      must_always = Array(metadata["must_always"])
      must_not = Array(metadata["must_not"])

      lines = []
      lines << "# Implementation Plan: #{title}"
      lines << ""
      lines << "Capability: `#{capability}`"
      lines << ""
      lines << "Status: `alpha-plan`"
      lines << ""
      lines << "## Summary"
      lines << ""
      lines << summary
      lines << ""
      lines << "## Objective"
      lines << ""
      lines << "Create proposal-local alpha artifacts that can be reviewed, verified, and later promoted through an explicit human-approved workflow."
      lines << ""
      lines << "## Scope"
      lines << ""
      lines << "- Generate alpha code only inside the proposal folder."
      lines << "- Generate a local verifier."
      lines << "- Generate test case scaffolding."
      lines << "- Generate a promotion checklist."
      lines << "- Do not register or load the alpha skill automatically."
      lines << ""
      lines << "## Derived first steps"
      lines << ""
      if first_steps.empty?
        lines << "- Define expected behavior."
        lines << "- Define inputs and outputs."
        lines << "- Define verification cases."
      else
        first_steps.each { |item| lines << "- #{item}" }
      end
      lines << ""
      lines << "## Mandatory boundaries"
      lines << ""
      must_always.each { |item| lines << "- #{item}" }
      lines << "- Keep generated artifacts proposal-local."
      lines << "- Require human review before promotion."
      lines << ""
      lines << "## Prohibited behavior"
      lines << ""
      must_not.each { |item| lines << "- #{item}" }
      lines << "- Do not modify production skill paths."
      lines << "- Do not modify registries."
      lines << "- Do not install packages or download models."
      lines << ""
      lines << "## Proposed alpha files"
      lines << ""
      lines << "```text"
      lines << "alpha/"
      lines << "├── README.md"
      lines << "├── implementation_plan.md"
      lines << "├── skill.rb"
      lines << "├── verify-alpha.rb"
      lines << "├── test_cases.json"
      lines << "├── promotion_checklist.md"
      lines << "└── alpha_manifest.json"
      lines << "```"
      lines << ""
      lines << "## Verification strategy"
      lines << ""
      lines << "- Validate all expected files exist."
      lines << "- Validate Ruby syntax."
      lines << "- Validate metadata boundaries."
      lines << "- Validate placeholder run output does not claim production readiness."
      lines << "- Validate manifest records no registration and no production modification."
      lines << ""
      lines << "## Promotion notes"
      lines << ""
      lines << "Promotion is intentionally out of scope for this alpha. A future promotion workflow must copy reviewed artifacts into production paths and update registries explicitly."
      lines.join("\n")
    end
  end
end
