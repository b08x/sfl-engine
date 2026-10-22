# frozen_string_literal: true

class Sfl
  hash_branch("review-queue") do |r|
    r.is do
      r.get do
        p = r.params
        modality = presence(p["modality"])
        limit = [p.fetch("limit", 50).to_i, 1].max
        offset = [p.fetch("offset", 0).to_i, 0].max

        result = ctx.review_queue_repo.pending(modality:, limit:, offset:)
        result.merge(limit:, offset:)
      end
    end

    r.on String do |id|
      r.is "decide" do
        r.post do
          body = r.params
          decision = body["decision"]
          decisions = SFL::Core::Types::ReviewQueueDecision.values
          raise ArgumentError, "decision must be one of #{decisions.join(', ')}" unless decisions.include?(decision)

          edited_text = body["edited_text"]
          raise ArgumentError, "edited_text is required for decision: edit" if decision == "edit" && presence(edited_text).nil?

          row = ctx.review_queue_repo.find(id)
          unless row
            response.status = 404
            next({ error: "review item not found", id: })
          end

          reviewer = body["reviewer"]
          clauses = apply_review_queue_decision(decision, row, edited_text)
          updated = ctx.review_queue_repo.decide(id:, decision:, edited_text:, reviewer:)

          out = { review: updated }
          out[:clauses] = clauses.map { |c| SFL::Core::Wire.dump(c) } if clauses
          out
        end
      end
    end
  end

  # approve -> synchronous: marks reviewed, storage untouched.
  # reject  -> synchronous: marks reviewed, clears the section's stored
  #            clauses via Pipeline's own replace_section(section_id, []).
  # edit    -> synchronous: Pipeline#compile(edited_text, ...) replaces the
  #            section's clauses in one transaction.
  private def apply_review_queue_decision(decision, row, edited_text)
    case decision
    when "reject"
      ctx.clause_store.replace_section(row[:section_id], [])
      nil
    when "edit"
      ctx.pipeline.compile(edited_text, section_id: row[:section_id], store: true, embed: true, resume: false)
        .value_or { |failure| raise "recompile failed for #{row[:section_id].inspect}: #{failure.inspect}" }
    end
  end
end
