#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/continuity_lab/retrieval"
require_relative "../lib/soul_core/continuity_lab/retrieval_ranked"

Lab = SoulCore::ContinuityLab
Retrieval = Lab::Retrieval
Ranked = Lab::RankedRetrieval

checks = 0
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  checks += 1
  puts "PASS: #{label}"
end

lineage = "a" * 32
args = lambda do |query, limit = 8, selected_lineage = lineage|
  { "lineage_id" => selected_lineage, "collection" => "corpus", "query" => query, "limit" => limit }
end
doc = lambda do |id, content, provenance = "operator_selected_source_not_authority"|
  { "id" => id, "revision" => 1, "content" => content, "provenance" => provenance }
end
state_for = lambda do |docs, selected_lineage = lineage|
  { "lineage_id" => selected_lineage, "corpus" => docs.map { |entry| entry.slice("id", "content") } }
end
search = ->(query, docs, limit = 8) { Ranked.search(state_for.call(docs), args.call(query, limit), "current", docs) }

exact_docs = [doc.call("first", "Signal amber signal", "exact-fixture")]
exact_args = args.call("amber signal")
check.call("full exact match is byte-for-byte legacy result",
  Ranked.search(state_for.call(exact_docs), exact_args, "current", exact_docs) == Retrieval.result(state_for.call(exact_docs), "search", exact_args, "current"))

mixed_docs = [doc.call("partial", "amber only"), doc.call("full", "amber signal")]
mixed_args = args.call("amber signal")
mixed = Ranked.search(state_for.call(mixed_docs), mixed_args, "current", mixed_docs)
check.call("exact full match suppresses partial fallback", mixed == Retrieval.result(state_for.call(mixed_docs), "search", mixed_args, "current") && mixed.dig("hits", 0, "id") == "full")

plural = search.call("BAG costs", [doc.call("plural", "Bags cost 8 credits")])
check.call("case folding and conservative bag/bags and cost/costs normalization", plural.dig("hits", 0, "matched_terms") == %w[bag cost])
singular_collisions = [
  ["status beacon", "statu beacon"],
  ["analysis signal", "analysi signal"],
  ["news beacon", "new beacon"],
  ["series beacon", "sery beacon"],
  ["species beacon", "specy beacon"]
].all? do |query, content|
  search.call(query, [doc.call("near-lexeme", content)]).fetch("hits").empty?
end
check.call("singular us/is forms and uninflected news/series/species do not collapse into false matches", singular_collisions)

stop_docs = [doc.call("distractor", "amber only"), doc.call("stop", "amber signal was recorded")]
stop = search.call("this amber signal", stop_docs)
check.call("stop words are excluded and one-term distractors fail the two-term floor",
  stop.dig("hits").map { |hit| hit.fetch("id") } == ["stop"] && stop.dig("hits", 0, "coverage") == 1.0)
check.call("genuine no-match returns an empty non-truncated fallback",
  search.call("amber signal", [doc.call("nothing", "violet valley")]) == { "ok" => true, "hits" => [], "truncated" => false })

ranked_docs = [
  doc.call("z-rare", "amber cobalt"),
  doc.call("b-tie", "amber cobalt"),
  doc.call("a-tie", "amber cobalt"),
  doc.call("a-common", "amber indigo")
] + 4.times.map { |index| doc.call("indigo-only-#{index}", "indigo filler") }
ranked = search.call("amber cobalt indigo", ranked_docs)
check.call("rarer overlap ranks ahead, then equal lexical scores break by source ID",
  ranked.dig("hits").map { |hit| hit.fetch("id") } == %w[a-tie b-tie z-rare a-common])

# With equal-frequency terms, source ID provides a stable deterministic order.
ties = search.call("opal quartz saffron", [doc.call("z", "opal quartz"), doc.call("a", "opal quartz")])
check.call("deterministic source-ID tie order", ties.dig("hits").map { |hit| hit.fetch("id") } == %w[a z])

unicode_text = "Straße beacon"
unicode = search.call("STRASSE beacon lantern", [doc.call("unicode", unicode_text)])
unicode_hit = unicode.fetch("hits").fetch(0)
check.call("Unicode case-fold matching keeps original character offsets and digest provenance",
  unicode_hit.fetch("matched_terms") == %w[strasse beacon] && unicode_hit.fetch("missing_terms") == ["lantern"] &&
    unicode_hit.fetch("matched_spans") == [
      { "term" => "strasse", "span" => [0, 6] }, { "term" => "beacon", "span" => [7, 13] }
    ] && unicode_hit.fetch("content_digest") == Digest::SHA256.hexdigest(unicode_text) &&
    unicode_hit.fetch("provenance") == "operator_selected_source_not_authority")
check.call("fallback reports missing terms and lexical overlap coverage",
  search.call("amber cobalt indigo", [doc.call("partial", "amber cobalt")]).dig("hits", 0).then do |hit|
    hit.fetch("matched_terms") == %w[amber cobalt] && hit.fetch("missing_terms") == ["indigo"] && hit.fetch("coverage") == (2.0 / 3)
  end)

many_docs = 10.times.map { |index| doc.call("source-#{index}", "amber cobalt #{'x' * 7000}") }
bounded = search.call("amber cobalt", many_docs, 8)
check.call("large result sets respect hit quota, byte quota, and explicit truncation",
  bounded.fetch("hits").length == 8 && bounded.fetch("truncated") &&
    Lab.encode(bounded).bytesize <= Retrieval::RESULT_BYTES)
quota_probe = search.call("amber cobalt", many_docs, 1)
check.call("requested result quota independently marks omitted ranked matches",
  quota_probe.fetch("hits").length == 1 && quota_probe.fetch("truncated"))

wrong_docs = [doc.call("x", "amber cobalt")]
wrong_lineage = Ranked.search(state_for.call(wrong_docs), args.call("amber cobalt", 8, "b" * 32), "current", wrong_docs)
check.call("lineage error remains the legacy result", wrong_lineage == { "ok" => false, "reason" => "cross_lineage_read" })

puts "Continuity Lab A17 ranked retrieval verifier: #{checks} checks passed"
