class Sfl
  hash_branch("synthesize") do |r|
    r.is do
      r.post do
        body = r.params
        query = body["query"]
        raise ArgumentError, "query is required" if query.nil? || query.to_s.strip.empty?

        filters = symbolize_keys(body.fetch("filters", {}))
        limit = [body.fetch("limit", 10).to_i, 1].max
        include_fallback = body.fetch("include_fallback", false)
        expand_ancestors = body.fetch("expand_ancestors", false)

        result = ctx.synthesizer.synthesize(query, filters:, limit:, include_fallback:, expand_ancestors:)
        SFL::Core::Wire.dump(result)
      end
    end
  end
end
