class Sfl
  STRING_CLAUSE_FILTERS = %w[source_type mood process_type].freeze
  NUMERIC_CLAUSE_FILTERS = %w[min_modality max_modality min_tenor max_tenor].freeze

  hash_branch("clauses") do |r|
    r.is "review-queue" do
      r.get do
        p = r.params
        limit = [p.fetch("limit", 50).to_i, 1].max
        offset = [p.fetch("offset", 0).to_i, 0].max

        result = ctx.annotation_review_repo.review_queue(limit:, offset:)
        result.merge(limit:, offset:)
      end
    end

    r.is do
      r.get do
        p = r.params
        limit = [p.fetch("limit", 50).to_i, 1].max
        offset = [p.fetch("offset", 0).to_i, 0].max

        result = ctx.clause_store.find_all(
          document_id: presence(p["document_id"]), annotation_source: presence(p["annotation_source"]),
          filters: build_retrieval_filters(p.slice(*STRING_CLAUSE_FILTERS, *NUMERIC_CLAUSE_FILTERS)),
          limit:, offset:
        )
        { clauses: result[:clauses].map { |c| SFL::Core::Wire.dump(c) }, total: result[:total], limit:, offset: }
      end
    end

    r.on String do |clause_id|
      r.is "review" do
        r.post do
          body = r.params
          decision = body["decision"]
          decisions = SFL::Core::Types::ReviewDecision.values
          unless decisions.include?(decision)
            raise ArgumentError, "decision must be one of #{decisions.join(', ')}"
          end

          review = ctx.clause_review_service.review(
            clause_id:, decision:, reviewer: body["reviewer"], notes: body["notes"]
          )
          unless review
            response.status = 404
            next({ error: "clause not found", id: clause_id })
          end

          SFL::Core::Wire.dump(review)
        end
      end
    end
  end
end
