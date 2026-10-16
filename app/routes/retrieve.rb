# frozen_string_literal: true

class Sfl
  hash_branch("retrieve") do |r|
    r.is do
      r.post do
        body = r.params
        query = body["query"]
        raise ArgumentError, "query is required" if query.nil? || query.to_s.strip.empty?

        filters = build_retrieval_filters(body.fetch("filters", {}))
        limit = [body.fetch("limit", 10).to_i, 1].max

        results = ctx.retriever.retrieve(SFL::Core::Types::RetrievalQuery.new(query:, limit:, filters:))
        { query:, results: results.map { |result| SFL::Core::Wire.dump(result) }, count: results.size }
      end
    end
  end
end
