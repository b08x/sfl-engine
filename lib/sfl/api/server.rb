# frozen_string_literal: true

require "json"
require "rack"
require "securerandom"

module SFL
  module API
    # Rack application for the SFL HTTP API — the deployable surface this
    # gives an FDE-style pitch: "here's a service I can deploy across
    # cloud/on-prem/hybrid," not just a library.
    #
    # Ported from legacy's Compiler::API::Server (Phase 5 sfl-api decision:
    # FIX AND KEEP), with the Gush/Sidekiq-dependent surface removed rather
    # than fixed, since sfl-jobs itself was dropped (Phase 5): no more
    # POST /workflows, GET /workflows/:id/status, or async branches of
    # POST /pipeline/compile and POST /clauses/:id/review. This also fixes
    # F2 (async compile writing a schema no consumer reads) by deletion —
    # the only compile path left is synchronous.
    #
    # Entry point: config.ru → `run SFL::API::Server.new(ctx)`
    #
    # Routes:
    #   GET  /health                   -> {status: "ok"}
    #   POST /pipeline/compile         -> AnnotatedClause[] (always sync)
    #   POST /retrieve                 -> {query:, results: RetrievalResult[], count:}
    #   POST /synthesize               -> SynthesisResult
    #   GET  /clauses                  -> {clauses:[], total:, limit:, offset:}
    #   GET  /clauses/review-queue     -> {clauses:[], total:, limit:, offset:} (annotation review queue)
    #   POST /clauses/:id/review       -> AnnotationReview (accepted/rejected/re_annotated, always sync)
    #   GET  /review-queue             -> {items:[], total:, limit:, offset:} (content-review queue)
    #   POST /review-queue/:id/decide  -> {review:, clauses?:} (approve/edit/reject)
    # rubocop:disable Metrics/ClassLength -- one Rack app with one small, single-purpose
    # method per route (parse body/params, call exactly one Context collaborator, wrap the
    # response) plus the shared CORS/JSON/error-handling plumbing every route needs; splitting
    # further would scatter one cohesive HTTP layer across multiple files for no readability gain
    # (same rationale PgClauseStore's own Metrics/ClassLength disable already documents).
    class Server
      CONTENT_JSON = { "content-type" => "application/json" }.freeze
      CLAUSE_REVIEW_RE = %r{\A/clauses/([^/]+)/review\z}
      REVIEW_QUEUE_DECIDE_RE = %r{\A/review-queue/([^/]+)/decide\z}
      STRING_CLAUSE_FILTERS = %w[source_type mood process_type].freeze
      NUMERIC_CLAUSE_FILTERS = %w[min_modality max_modality min_tenor max_tenor].freeze
      REVIEW_DECISIONS = Core::Types::ReviewDecision.values.freeze
      REVIEW_QUEUE_DECISIONS = Core::Types::ReviewQueueDecision.values.freeze

      # Dev-only allowlist: same rationale as legacy's Server — no
      # rack-cors dependency for three headers, revisit if a production
      # origin needs adding.
      CORS_ORIGINS = %w[http://localhost:3000 http://127.0.0.1:3000].freeze
      CORS_HEADERS = {
        "access-control-allow-methods" => "GET, POST, OPTIONS",
        "access-control-allow-headers" => "content-type",
      }.freeze

      # @param ctx [API::Context]
      def initialize(ctx)
        @ctx = ctx
      end

      def call(env)
        req = Rack::Request.new(env)
        origin = req.get_header("HTTP_ORIGIN")

        return preflight(origin) if req.request_method == "OPTIONS"

        status, headers, body = respond(req)
        [status, with_cors(headers, origin), body]
      end

      attr_reader :ctx

      private def respond(req)
        dispatch(req)
      rescue ArgumentError => e
        json(400, { error: e.message })
      rescue => e
        warn "[ERROR] API #{e.class}: #{e.message}"
        json(500, { error: "Internal Server Error", message: e.message })
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      # One flat routing table, one `in` clause per route; splitting this into smaller methods
      # would only relocate the branch count, not reduce it.
      private def dispatch(req)
        case [req.request_method, req.path_info]
        in ["GET", "/health"]
          json(200, { status: "ok" })
        in ["POST", "/pipeline/compile"]
          compile_pipeline(req)
        in ["POST", "/retrieve"]
          retrieve(req)
        in ["POST", "/synthesize"]
          synthesize(req)
        in ["GET", "/clauses/review-queue"]
          annotation_review_queue(req)
        in ["GET", "/clauses"]
          list_clauses(req)
        in ["POST", CLAUSE_REVIEW_RE]
          review_clause(req.path_info.match(CLAUSE_REVIEW_RE)[1], req)
        in ["GET", "/review-queue"]
          review_queue_list(req)
        in ["POST", REVIEW_QUEUE_DECIDE_RE]
          review_queue_decide(req.path_info.match(REVIEW_QUEUE_DECIDE_RE)[1], req)
        else
          json(404, { error: "Not Found", path: req.path_info })
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # POST /pipeline/compile
      #
      # Body: {text:, document_id:, store:, embed:}
      # rubocop:disable Metrics/AbcSize -- one flat validate/default/compile/respond
      # sequence; each line does exactly one of those four things.
      private def compile_pipeline(req)
        body = parse_body(req)
        text = body["text"]
        raise ArgumentError, "text is required" if text.nil? || text.to_s.strip.empty?

        document_id = body["document_id"] || "api-#{SecureRandom.uuid}"
        store = body.fetch("store", false)
        embed = body.fetch("embed", false)

        clauses = ctx.pipeline.compile(text, document_id:, store:, embed:, resume: false)
          .value_or { |failure| raise "compile failed for #{document_id.inspect}: #{failure.inspect}" }
        json(200, clauses.map { |c| Core::Wire.dump(c) })
      end
      # rubocop:enable Metrics/AbcSize

      # POST /retrieve
      #
      # Body: {query:, filters?: {min_modality:, max_modality:, min_tenor:,
      #   max_tenor:, mood:, process_type:, source_type:}, limit?:}
      # rubocop:disable Metrics/AbcSize -- one flat validate/build-query/retrieve/respond sequence.
      private def retrieve(req)
        body = parse_body(req)
        query = body["query"]
        raise ArgumentError, "query is required" if query.nil? || query.to_s.strip.empty?

        filters = build_retrieval_filters(body.fetch("filters", {}))
        limit = [body.fetch("limit", 10).to_i, 1].max

        results = ctx.retriever.retrieve(Core::Types::RetrievalQuery.new(query:, limit:, filters:))
        json(200, { query:, results: results.map { |r| Core::Wire.dump(r) }, count: results.size })
      end
      # rubocop:enable Metrics/AbcSize

      # POST /synthesize
      #
      # Body: {query:, filters?:, limit?:, include_fallback?:}
      # rubocop:disable Metrics/AbcSize -- one flat validate/build-kwargs/synthesize/respond sequence.
      private def synthesize(req)
        body = parse_body(req)
        query = body["query"]
        raise ArgumentError, "query is required" if query.nil? || query.to_s.strip.empty?

        filters = symbolize_keys(body.fetch("filters", {}))
        limit = [body.fetch("limit", 10).to_i, 1].max
        include_fallback = body.fetch("include_fallback", false)

        result = ctx.synthesizer.synthesize(query, filters:, limit:, include_fallback:)
        json(200, Core::Wire.dump(result))
      end
      # rubocop:enable Metrics/AbcSize

      # GET /clauses
      #
      # Query params: document_id, annotation_source, source_type, mood,
      # process_type, min_modality, max_modality, min_tenor, max_tenor,
      # limit (default 50), offset (default 0).
      # rubocop:disable Metrics/AbcSize -- one flat paginate/filter/query/respond sequence.
      private def list_clauses(req)
        p = req.params
        limit = [p.fetch("limit", 50).to_i, 1].max
        offset = [p.fetch("offset", 0).to_i, 0].max

        result = ctx.clause_store.find_all(
          document_id: presence(p["document_id"]), annotation_source: presence(p["annotation_source"]),
          filters: build_retrieval_filters(p.slice(*STRING_CLAUSE_FILTERS, *NUMERIC_CLAUSE_FILTERS)),
          limit:, offset:
        )
        json(200, { clauses: result[:clauses].map { |c| Core::Wire.dump(c) }, total: result[:total], limit:, offset: })
      end
      # rubocop:enable Metrics/AbcSize

      # GET /clauses/review-queue
      #
      # Query params: limit (default 50), offset (default 0). The
      # annotation-confidence queue (PgAnnotationReviewRepository), not the
      # content-review queue GET /review-queue serves.
      private def annotation_review_queue(req)
        p = req.params
        limit = [p.fetch("limit", 50).to_i, 1].max
        offset = [p.fetch("offset", 0).to_i, 0].max

        result = ctx.annotation_review_repo.review_queue(limit:, offset:)
        json(200, result.merge(limit:, offset:))
      end

      # POST /clauses/:id/review
      #
      # Body: {decision: "accepted"|"rejected"|"re_annotated", reviewer?:, notes?:}
      #   accepted/rejected -> records the audit row only, 200 with the AnnotationReview.
      #   re_annotated      -> re-runs Pass 2 only (not a full recompile) against the
      #                        clause's already-stored syntactic+ideational payload,
      #                        writes the new interpersonal payload, then records the
      #                        audit row. Always synchronous now that sfl-jobs is
      #                        dropped -- legacy's own ReannotateClauseJob comment
      #                        already noted Pass 2 "could run inline," it just kept
      #                        job-consistency instead; there's no longer a job to be
      #                        consistent with.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat validate/find/
      # (maybe re-annotate)/record/respond sequence.
      private def review_clause(clause_id, req)
        body = parse_body(req)
        decision = body["decision"]
        unless REVIEW_DECISIONS.include?(decision)
          raise ArgumentError, "decision must be one of #{REVIEW_DECISIONS.join(', ')}"
        end

        clause = ctx.clause_store.find(clause_id)
        return json(404, { error: "clause not found", id: clause_id }) unless clause

        reviewer = body["reviewer"]
        notes = body["notes"]
        original_source = clause.interpersonal.annotation_source

        reannotate_clause(clause) if decision == "re_annotated"

        review = ctx.annotation_review_repo.record_review(
          clause_id:, decision:, original_annotation_source: original_source, reviewer:, notes:
        )
        json(200, Core::Wire.dump(review))
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private def reannotate_clause(clause)
        annotated = ctx.pass_two.annotate(clause.syntactic, clause.ideational)
        ctx.clause_store.update_interpersonal(clause.id, annotated.interpersonal)
      end

      # GET /review-queue
      #
      # Query params: modality (optional filter), limit (default 50), offset (default 0).
      private def review_queue_list(req)
        p = req.params
        modality = presence(p["modality"])
        limit = [p.fetch("limit", 50).to_i, 1].max
        offset = [p.fetch("offset", 0).to_i, 0].max

        result = ctx.review_queue_repo.pending(modality:, limit:, offset:)
        json(200, result.merge(limit:, offset:))
      end

      # POST /review-queue/:id/decide
      #
      # Body: {decision: "approve"|"edit"|"reject", edited_text?:, reviewer?:}
      #   approve -> synchronous: marks reviewed, storage untouched.
      #   reject  -> synchronous: marks reviewed, clears the document's stored
      #              clauses (Pipeline's own write path, replace_document with
      #              an empty array, rather than a separate delete method --
      #              same "idempotency lives in the interface" contract
      #              PgClauseStore#replace_document already documents).
      #   edit    -> synchronous: Pipeline#compile(edited_text, ...) replaces
      #              the document's clauses in one transaction (Pipeline's
      #              own persist step already deletes-then-inserts -- no
      #              separate pre-delete needed here).
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat validate/find/
      # apply-decision/record/respond sequence.
      private def review_queue_decide(id, req)
        body = parse_body(req)
        decision = body["decision"]
        unless REVIEW_QUEUE_DECISIONS.include?(decision)
          raise ArgumentError, "decision must be one of #{REVIEW_QUEUE_DECISIONS.join(', ')}"
        end

        edited_text = body["edited_text"]
        if decision == "edit" && presence(edited_text).nil?
          raise ArgumentError, "edited_text is required for decision: edit"
        end

        row = ctx.review_queue_repo.find(id)
        return json(404, { error: "review item not found", id: }) unless row

        reviewer = body["reviewer"]
        clauses = apply_review_queue_decision(decision, row, edited_text)
        updated = ctx.review_queue_repo.decide(id:, decision:, edited_text:, reviewer:)

        response = { review: updated }
        response[:clauses] = clauses.map { |c| Core::Wire.dump(c) } if clauses
        json(200, response)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private def apply_review_queue_decision(decision, row, edited_text)
        case decision
        when "reject"
          ctx.clause_store.replace_document(row[:document_id], [])
          nil
        when "edit"
          ctx.pipeline.compile(edited_text, document_id: row[:document_id], store: true, embed: true, resume: false)
            .value_or { |failure| raise "recompile failed for #{row[:document_id].inspect}: #{failure.inspect}" }
        end
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat literal, one field per
      # RetrievalFilters attribute.
      private def build_retrieval_filters(raw)
        f = symbolize_keys(raw)
        Core::Types::RetrievalFilters.new(
          **{
            mood: presence(f[:mood]),
            process_type: presence(f[:process_type]),
            source_type: presence(f[:source_type]),
            min_modality: numeric(f[:min_modality]),
            max_modality: numeric(f[:max_modality]),
            min_tenor: numeric(f[:min_tenor]),
            max_tenor: numeric(f[:max_tenor]),
          }.compact
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private def presence(value)
        value.to_s.strip.empty? ? nil : value
      end

      private def numeric(value)
        (value.nil? || value.to_s.strip.empty?) ? nil : value.to_f
      end

      private def preflight(origin)
        [204, with_cors({}, origin), []]
      end

      private def with_cors(headers, origin)
        return headers unless CORS_ORIGINS.include?(origin)

        headers.merge(CORS_HEADERS).merge("access-control-allow-origin" => origin)
      end

      private def parse_body(req)
        raw = req.body.read
        return {} if raw.nil? || raw.empty?

        JSON.parse(raw)
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid JSON body: #{e.message}"
      end

      private def symbolize_keys(hash)
        hash.transform_keys(&:to_sym)
      end

      private def json(status, body)
        [status, CONTENT_JSON, [JSON.dump(body)]]
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
