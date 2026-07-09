
# Skill Registry `to_h` Repair

This repair addresses a broken documented command:

```bash
ruby bin/soul skills
```

## Issue

`lib/soul_core/app.rb` calls:

```ruby
SkillRegistry.new.to_h
```

but `SkillRegistry` only exposed `list` and `fetch`.

That caused:

```text
NoMethodError: undefined method `to_h`
```

It also broke `make test-soul` when that target invokes `ruby bin/soul skills`.

## Fix

Add a small compatibility method:

```ruby
def to_h
  skills = list
  return skills if skills.is_a?(Hash)

  {"skills" => skills}
end
```

This preserves the existing registry behavior and gives the CLI a JSON-serializable object.

## Scope

This repair changes:

```text
lib/soul_core/skill_registry.rb
scripts/verify-skill-registry-to-h-repair.rb
docs/maintenance/SKILL_REGISTRY_TO_H_REPAIR.md
```
