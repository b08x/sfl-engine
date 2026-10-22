# frozen_string_literal: true

class Sfl
  hash_branch("pipeline") do |r|
    r.is "compile" do
      r.post do
        body = reject_legacy_id(r.params)
        text = body["text"]
        raise ArgumentError, "text is required" if text.nil? || text.to_s.strip.empty?

        section_id = body["section_id"] || "api-#{SecureRandom.uuid}"
        store = body.fetch("store", false)
        embed = body.fetch("embed", false)

        clauses = ctx.pipeline.compile(text, section_id:, store:, embed:, resume: false)
          .value_or { |failure| raise "compile failed for #{section_id.inspect}: #{failure.inspect}" }
        clauses.map { |c| SFL::Core::Wire.dump(c) }
      end
    end
  end
end
