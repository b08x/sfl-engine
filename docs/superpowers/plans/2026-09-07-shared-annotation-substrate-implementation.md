# Shared Annotation Substrate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn sfl-engine into the one deployable annotation/retrieval substrate — reachable over HTTP (Roda) and remote MCP from the same in-process pipeline — and make phantom-agent a client of it instead of running its own single-LLM-call SFL annotator.

**Architecture:** Replace `lib/sfl/api/server.rb`'s hand-rolled `case/in` router with a Roda routing tree that calls the exact same private handler methods (behavior-preserving rewrite, driven by the existing `spec/api/server_spec.rb`). Add a new `SFL::API::McpServer` built on the official `mcp` gem's `StreamableHTTPTransport`, mounted as a sub-app under `/mcp` inside that same Roda tree, sharing the already-built `pipeline`/`retriever` objects — no second process, no internal HTTP hop. Add Podman Quadlet unit files for `sfl-postgres`/`sfl-api` so the combined Ruby+spaCy image (already built by `docker/api.Dockerfile`) can run under systemd. On the phantom-agent side, add a small `sfl_client` module that calls the new HTTP endpoint, then delete `src/phantom_agent/annotator/` entirely and rewire its two callers (`cli.py`'s `annotate-sfl`, and the `ui/annotation_stream` TUI) to use the client.

**Tech Stack:** Ruby 4.0.1, Roda 3.107 (new), Falcon 0.57 (unchanged), the `mcp` gem 1.5.0 (new, official modelcontextprotocol Ruby SDK), Rack 3.1 (unchanged), RSpec + Rack::Test (unchanged). Python 3.11+, `httpx` (new dependency) for the phantom-agent client, `pytest` (unchanged).

**Spec:** `/home/b08x/WorkspaceV3/sfl-engine/docs/superpowers/specs/2026-09-06-shared-annotation-substrate-design.md`

## Global Constraints

- `config.ru`'s `run SFL::API::Server.new(ctx, debug_errors:, cors_origins:)` line does not change shape — only what `Server` does internally changes (spec Component 1).
- No tenant/agent-identity partitioning anywhere in this work — storage stays keyed by topic, and the MCP server's shared context carries no per-caller identity (spec Non-goals, spec Data Model).
- HTTP and MCP share the same in-process `pipeline`/`retriever` objects built once at boot — no internal network hop between the two transports (spec Shape).
- Sidecar transport failures keep their existing crash-and-retry-once policy (`SpacySidecarParser#fail_or_retry`) — unchanged by this work (spec Error Handling).
- Migrations remain a deliberate, explicit action (`bundle exec rake db:migrate` / a one-shot Quadlet unit), never automatic on boot (AGENTS.md's "No auto-migration" decision, carried into spec Component 3).
- Every new Ruby file: `# frozen_string_literal: true`, double-quoted strings, 2-space indent, Zeitwerk-compliant naming (AGENTS.md Key Conventions).
- Every gem version added below was installed and verified against this toolchain during planning (Ruby 4.0.1, per this codebase's own "verified compatible... rather than assumed from memory" convention) — not copied from documentation.

---

## Task 1: Roda-based HTTP routing

**Files:**
- Modify: `Gemfile` (add `gem "roda"`)
- Modify: `lib/sfl/api/server.rb:1-355` (replace `dispatch`/`respond`'s routing table; every other private method is unchanged)
- Modify: `AGENTS.md:15` ("HTTP API" line — mention Roda)
- Test: `spec/api/server_spec.rb` (unchanged — this is the characterization suite the rewrite is driven against; it must pass byte-for-byte identical to today)

**Interfaces:**
- Consumes: `SFL::API::Context` (`lib/sfl/api/context.rb`) — unchanged, `Context#pipeline`/`#retriever`/`#synthesizer`/`#clause_store`/`#review_queue_repo`/`#annotation_review_repo`/`#pass_two`/`#clause_review_service`.
- Produces: `SFL::API::Server.new(ctx, debug_errors: false, cors_origins: [])` → an object responding to `#call(env)` returning a Rack triplet. This exact constructor signature is what Task 2 and `config.ru` both call — do not change it.

This is a **behavior-preserving rewrite**, not new behavior: `spec/api/server_spec.rb` already exercises every route, the CORS preflight, the 400/404/500 error mapping, and `debug_errors:`. Rather than writing new tests first, this task drives the rewrite against that existing suite (a legitimate variant of red/green: red is "the old implementation passes, prove the new one does too," not "no implementation exists yet").

- [ ] **Step 1: Confirm the baseline passes before touching anything**

Run: `bundle exec rspec spec/api/server_spec.rb`
Expected: all examples pass against the current hand-rolled `Server`. This is your regression baseline — if anything is red here, stop and fix the environment before proceeding, since Task 1's exit criterion is "still all green."

- [ ] **Step 2: Add the `roda` gem**

Add to `Gemfile`, in the "Phase 5 sfl-api" gem group (right after the existing `falcon`/`rack` lines, `lib/sfl/api/server.rb`'s Gemfile section):

```ruby
# Phase 8 shared-annotation-substrate: Roda replaces the hand-rolled Rack
# dispatch table as the HTTP routing layer. Roda and Falcon are not
# alternatives — Roda generates a Rack app, Falcon is the async server that
# runs it — so config.ru's `run` line is unaffected.
gem "roda", "~> 3.107"
```

Run: `bundle install`
Expected: `Gemfile.lock` gains a `roda (3.107.x)` entry with no other version bumps.

- [ ] **Step 3: Rewrite `lib/sfl/api/server.rb`'s routing layer**

Replace the file's `require` line and the `dispatch`/routing portion. Everything from `CONTENT_JSON = ...` through the end of `private def compile_pipeline` onward (all the per-route handler bodies: `compile_pipeline`, `retrieve`, `synthesize`, `list_clauses`, `annotation_review_queue`, `review_clause`, `review_queue_list`, `review_queue_decide`, `apply_review_queue_decision`, `build_retrieval_filters`, `presence`, `numeric`, `preflight`, `with_cors`, `parse_body`, `symbolize_keys`, `json`) stays **exactly as it is today, unchanged, copy-pasted verbatim** — only their signatures already accept a `Rack::Request`-like object, and Roda's request object (`Roda::RodaRequest`) is itself a `Rack::Request` subclass, so nothing about how they read `req.params`/`req.body`/`req.path_info` needs to change.

What changes is `initialize`, `call`, `respond`, and `dispatch`:

```ruby
# frozen_string_literal: true

require "json"
require "rack"
require "roda"
require "securerandom"

module SFL
  module API
    # Rack application for the SFL HTTP API — the deployable surface this
    # gives an FDE-style pitch: "here's a service I can deploy across
    # cloud/on-prem/hybrid," not just a library.
    #
    # Phase 8 (shared-annotation-substrate spec): Roda replaces the hand-rolled
    # `case/in` dispatch table as the routing layer only. Every other concern
    # this class owns — CORS, the 400/404/500 error mapping, debug_errors,
    # request-body parsing, and every route's actual handler — is completely
    # unchanged from the pre-Roda version; #dispatch just hands the request to
    # a Roda routing tree instead of a manual `case [method, path]` match, and
    # each matched branch calls the same private method as before. Roda's
    # request object (`Roda::RodaRequest`) is itself a `Rack::Request`
    # subclass, so every handler below still reads `req.params`/`req.body`/
    # `req.path_info` exactly as it did pre-Roda.
    #
    # A fresh anonymous Roda subclass is built per Server instance (#build_roda_app)
    # rather than using Roda's usual "one named subclass, configured once at
    # class-load time" pattern: config.ru calls `SFL::API::Server.new(ctx, ...)`
    # and the spec's own constraint says that line's shape must not change, so
    # Server needs to stay a plain object you construct with `.new(ctx, ...)`,
    # not a Roda class you `run` directly. The anonymous subclass's `route`
    # block closes over `outer` (this Server instance) and calls back into its
    # private handler methods — Roda supplies path-pattern matching only.
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
    #   /mcp/*                         -> remote MCP server (see McpServer, Task 2) mounted as a sub-app
    # rubocop:disable Metrics/ClassLength -- one Rack app with one small, single-purpose
    # method per route (parse body/params, call exactly one Context collaborator, wrap the
    # response) plus the shared CORS/JSON/error-handling plumbing every route needs; splitting
    # further would scatter one cohesive HTTP layer across multiple files for no readability gain
    # (same rationale PgClauseStore's own Metrics/ClassLength disable already documents).
    class Server
      CONTENT_JSON = { "content-type" => "application/json" }.freeze
      STRING_CLAUSE_FILTERS = %w[source_type mood process_type].freeze
      NUMERIC_CLAUSE_FILTERS = %w[min_modality max_modality min_tenor max_tenor].freeze
      REVIEW_DECISIONS = Core::Types::ReviewDecision.values.freeze
      REVIEW_QUEUE_DECISIONS = Core::Types::ReviewQueueDecision.values.freeze

      CORS_HEADERS = {
        "access-control-allow-methods" => "GET, POST, OPTIONS",
        "access-control-allow-headers" => "content-type",
      }.freeze

      # @param ctx [API::Context]
      # @param debug_errors [Boolean] include raw exception messages in 500 responses
      #   (Boot::Result#api_debug_errors, SFL_API_DEBUG_ERRORS — issue #3). False in every
      #   real deployment; the generic response + logged request_id is the supported way to
      #   correlate a client-reported failure with server-side logs.
      # @param cors_origins [Array<String>] allowed Origin values (Boot::Result#api_cors_origins,
      #   SFL_API_CORS_ORIGINS — issue #35).
      def initialize(ctx, debug_errors: false, cors_origins: [])
        @ctx = ctx
        @debug_errors = debug_errors
        @cors_origins = cors_origins
        @roda_app = build_roda_app
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
        request_id = SecureRandom.uuid
        warn "[ERROR] API #{e.class} request_id=#{request_id} #{req.request_method} #{req.path_info}: " \
          "#{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
        body = { error: "Internal Server Error", request_id: }
        body[:message] = e.message if @debug_errors
        json(500, body)
      end

      private def dispatch(req)
        @roda_app.call(req.env)
      end

      # Builds one anonymous Roda subclass per Server instance. `outer` is
      # this Server, captured by the route block's closure; every branch
      # below calls back into outer's private handler methods (unchanged
      # from the pre-Roda implementation) and wraps the result in `r.halt`,
      # since Roda does not auto-detect a bare `[status, headers, body]`
      # array as a Rack response the way returning it from `#call` does —
      # `r.halt` is the documented way to hand Roda a literal Rack triplet.
      #
      # Route order matters in two places where a broader `r.on "X", String`
      # matcher would otherwise swallow a more specific sibling route before
      # it gets a chance to match (verified live during planning): `GET
      # /clauses/review-queue` must be checked before `r.on "clauses", String`
      # (whose String segment would otherwise capture "review-queue" as an
      # :id), and the bare `GET /clauses` list route is unaffected either way
      # since it never has a second path segment.
      private def build_roda_app
        outer = self
        Class.new(Roda) do
          route do |r|
            r.get "health" do
              r.halt outer.send(:json, 200, { status: "ok" })
            end

            r.post "pipeline", "compile" do
              r.halt outer.send(:compile_pipeline, r)
            end

            r.post "retrieve" do
              r.halt outer.send(:retrieve, r)
            end

            r.post "synthesize" do
              r.halt outer.send(:synthesize, r)
            end

            r.get "clauses", "review-queue" do
              r.halt outer.send(:annotation_review_queue, r)
            end

            r.get "clauses" do
              r.halt outer.send(:list_clauses, r)
            end

            r.on "clauses", String do |id|
              r.post "review" do
                r.halt outer.send(:review_clause, id, r)
              end
            end

            r.get "review-queue" do
              r.halt outer.send(:review_queue_list, r)
            end

            r.on "review-queue", String do |id|
              r.post "decide" do
                r.halt outer.send(:review_queue_decide, id, r)
              end
            end

            r.on "mcp" do
              r.run outer.ctx.mcp_transport
            end
          end
        end
      end

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
      #                        consistent with. # -- one flat validate/delegate/respond sequence; the
      # find/(maybe re-annotate)/record transaction itself lives in ClauseReviewService (#2).
      private def review_clause(clause_id, req)
        body = parse_body(req)
        decision = body["decision"]
        unless REVIEW_DECISIONS.include?(decision)
          raise ArgumentError, "decision must be one of #{REVIEW_DECISIONS.join(', ')}"
        end

        review = ctx.clause_review_service.review(
          clause_id:, decision:, reviewer: body["reviewer"], notes: body["notes"]
        )
        return json(404, { error: "clause not found", id: clause_id }) unless review

        json(200, Core::Wire.dump(review))
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
        return headers unless @cors_origins.include?(origin)

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
```

Note: `build_roda_app` references `outer.ctx.mcp_transport`, which doesn't exist on `Context` yet — that's Task 2. For this step, temporarily comment out the `r.on "mcp" do ... end` block (or leave it — Task 2 lands before this task's final commit if done in the same session; if executing tasks strictly in order, comment it out now and uncomment in Task 2's Step, noting that in Task 2's steps below).

- [ ] **Step 4: Run the full characterization suite against the rewrite**

Run: `bundle exec rspec spec/api/server_spec.rb`
Expected: all examples pass, identical to Step 1's baseline. If anything fails, the failure is almost always one of: (a) the `mcp` route block left uncommented with no `ctx.mcp_transport` yet (comment it out per Step 3's note), or (b) a route ordering issue — re-check that `r.get "clauses", "review-queue"` precedes `r.on "clauses", String`.

- [ ] **Step 5: Update AGENTS.md's HTTP API line**

In `AGENTS.md:15`, change:
```
- **HTTP API**: Falcon via `exe/sfl-api` → `config.ru`. **CLI**: `exe/sfl-analyze` subcommands conversation, documentation, knowledge-base, context.
```
to:
```
- **HTTP API**: Roda routes served by Falcon via `exe/sfl-api` → `config.ru`; the same Roda tree mounts the remote MCP server under `/mcp` (see McpServer). **CLI**: `exe/sfl-analyze` subcommands conversation, documentation, knowledge-base, context.
```

- [ ] **Step 6: Run full verification and commit**

Run: `bundle exec rake`
Expected: spec, rubocop, and zeitwerk:check all pass. Fix any rubocop offenses in the rewritten sections (the `rubocop:disable`/`enable` pairs above are copied from the original file and should still cover the same methods).

```bash
git add Gemfile Gemfile.lock lib/sfl/api/server.rb AGENTS.md
git commit -m "$(cat <<'EOF'
refactor(api): replace hand-rolled Rack dispatch with Roda routing

Same routes, same handlers, same error/CORS behavior -- spec/api/server_spec.rb
passes unchanged. Roda is a routing layer only; config.ru's `run
SFL::API::Server.new(ctx, ...)` line is untouched. Also reserves a `/mcp`
mount point for the remote MCP server landing in the next task.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NQUGhhhsJVnR2x7hkJ2V8R
EOF
)"
```

---

## Task 2: Remote MCP server

**Files:**
- Create: `lib/sfl/api/mcp_server.rb`
- Modify: `lib/sfl/api/context.rb:26-30,57-80` (add `:mcp_transport` field, build it)
- Modify: `lib/sfl/api/server.rb` (uncomment the `r.on "mcp"` block from Task 1 Step 3)
- Modify: `Gemfile` (add `gem "mcp"`)
- Modify: `AGENTS.md:15` (mention MCP explicitly, already partly done in Task 1)
- Test: `spec/api/mcp_server_spec.rb` (new)

**Interfaces:**
- Consumes: `pipeline` (`SFL::Core::Pipeline#compile(text, document_id:, store:, embed:, resume:) -> Dry::Monads::Result`), `retriever` (`SFL::Store::PgHybridRetriever#retrieve(SFL::Core::Types::RetrievalQuery) -> Array<RetrievalResult>`), `SFL::Core::Wire.dump(obj) -> Hash` — all already used identically in `lib/sfl/api/server.rb`.
- Produces: `SFL::API::McpServer.build(pipeline:, retriever:) -> MCP::Server::Transports::StreamableHTTPTransport` — a Rack app, mountable via `r.run`. Consumed by `Context.build` (this task) and `Server#build_roda_app` (Task 1).

- [ ] **Step 1: Add the `mcp` gem**

Add to `Gemfile`, right after the new `roda` line from Task 1:

```ruby
# Phase 8 shared-annotation-substrate: the official modelcontextprotocol Ruby
# SDK. Only the Streamable HTTP transport is used (not stdio) -- Hermes-agent
# and phantom-agent are separately-deployed services, not local subprocesses
# this process could spawn. StreamableHTTPTransport is a Rack app in its own
# right (requires "rack", already a dependency), mounted under /mcp inside
# the same Roda tree Server builds -- no second process, no internal HTTP hop.
gem "mcp", "~> 1.5"
```

Run: `bundle install`
Expected: `Gemfile.lock` gains `mcp (1.5.x)` plus its own dependencies (`json_schemer`, `hana`, `simpleidn`) with no other version bumps.

- [ ] **Step 2: Write the failing spec for the annotate tool**

Create `spec/api/mcp_server_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "dry/monads"

RSpec.describe SFL::API::McpServer do
  include Dry::Monads[:result]

  let(:pipeline) { instance_double(SFL::Core::Pipeline) }
  let(:retriever) { instance_double(SFL::Store::PgHybridRetriever) }
  let(:transport) { described_class.build(pipeline:, retriever:) }

  def call_tool(name, arguments)
    request = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name:, arguments: } }
    env = Rack::MockRequest.env_for(
      "/", method: "POST", input: JSON.dump(request),
      "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json"
    )
    _status, _headers, body = transport.call(env)
    JSON.parse(body.first)
  end

  # rubocop:disable Metrics/MethodLength -- one full AnnotatedClause fixture literal, matching
  # spec/api/server_spec.rb's own build_clause disable rationale.
  def build_clause(id: "c-1", document_id: "doc-1")
    SFL::Core::Types::AnnotatedClause.new(
      id:, text: "The system processed it.",
      syntactic: SFL::Core::Types::SyntacticClause.new(
        id:, text: "The system processed it.", tokens: [], groups: [], root_index: 0,
        sentence_index: 0, document_id:
      ),
      ideational: SFL::Core::Types::IdeationalPayload.new(
        clause_id: id, process_type: "material", participants: [], circumstances: [], raw_transitivity: {}
      ),
      interpersonal: SFL::Core::Types::InterpersonalPayload.new(
        clause_id: id, mood: "declarative", modality_weight: 0.7, tenor: 0.4, speaker_attitude: "neutral",
        reasoning: "clear", annotation_source: "llm", reasoning_trace: nil
      ),
      document_id:, compiled_at: Time.at(1_700_000_000).utc
    )
  end
  # rubocop:enable Metrics/MethodLength

  describe "annotate tool" do
    it "compiles the text through the shared pipeline and returns the payload with provenance" do
      clause = build_clause
      allow(pipeline).to receive(:compile)
        .with("hello", document_id: instance_of(String), store: false, embed: false, resume: false)
        .and_return(Success([clause]))

      result = call_tool("annotate", { text: "hello" })

      payload = JSON.parse(result.dig("result", "content", 0, "text"))
      expect(payload.first["id"]).to eq("c-1")
      expect(payload.first["interpersonal"]["annotation_source"]).to eq("llm")
    end

    it "surfaces a compile failure as an MCP tool error rather than raising" do
      allow(pipeline).to receive(:compile).and_return(Failure(:sidecar_timeout))

      result = call_tool("annotate", { text: "hello" })

      expect(result.dig("result", "isError")).to be true
    end
  end

  describe "retrieve_stance_filtered tool" do
    it "applies interpersonal-payload filters and returns ranked results" do
      retrieval_result = SFL::Core::Types::RetrievalResult.new(
        clause_id: "c-1", text: "hi", document_id: "doc-1", rrf_score: 0.9
      )
      allow(retriever).to receive(:retrieve)
        .with(an_object_having_attributes(query: "hi", limit: 5,
          filters: an_object_having_attributes(min_modality: 0.5)))
        .and_return([retrieval_result])

      result = call_tool("retrieve_stance_filtered",
        { query: "hi", limit: 5, filters: { min_modality: 0.5 } })

      payload = JSON.parse(result.dig("result", "content", 0, "text"))
      expect(payload.first["clause_id"]).to eq("c-1")
    end
  end
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/api/mcp_server_spec.rb`
Expected: `NameError: uninitialized constant SFL::API::McpServer` (or similar autoload failure) — `lib/sfl/api/mcp_server.rb` doesn't exist yet.

- [ ] **Step 4: Implement `SFL::API::McpServer`**

Create `lib/sfl/api/mcp_server.rb`:

```ruby
# frozen_string_literal: true

require "mcp"
require "mcp/server/transports/streamable_http_transport"
require "securerandom"

module SFL
  module API
    # Remote MCP surface over the substrate's pipeline/retriever, mounted
    # under /mcp inside the same Roda tree lib/sfl/api/server.rb builds (Server
    # constructs Context first, then reads ctx.mcp_transport and mounts it
    # via `r.run` -- no second process, no internal HTTP hop between HTTP and
    # MCP, per the shared-annotation-substrate spec's Shape section).
    #
    # Transport is StreamableHTTPTransport (remote HTTP/SSE), not stdio:
    # phantom-agent and future consumers (Hermes-agent) are separately
    # deployed services, not local subprocesses this process could spawn.
    # `stateless: true` + `enable_json_response: true`: every tool call here
    # is a single request/response with no server-to-client follow-up
    # (sampling, elicitation), so there is nothing a stateful session would
    # buy -- and JSON responses (vs. an SSE stream) are what a plain HTTP
    # client (phantom-agent's `httpx` call) expects without needing an
    # event-stream parser.
    #
    # ToolContext (not API::Context) is what each tool's `server_context:`
    # resolves to -- deliberately narrower than the full API::Context Server
    # uses: an MCP client only ever needs pipeline/retriever, and giving it
    # clause_review_service or the raw db-backed repos would let a remote
    # caller reach mutation/audit paths this surface was never designed to
    # expose. Least privilege by construction, not by convention.
    module McpServer
      ToolContext = Struct.new(:pipeline, :retriever, keyword_init: true)

      # tools/call "annotate" -- runs text through Pass 1 + Pass 2 and returns
      # the ideational + interpersonal payloads with provenance. Always
      # store: false, embed: false: an MCP annotate call is a one-off
      # inspection, not an ingestion write -- a caller that wants the result
      # persisted uses POST /pipeline/compile with store: true instead.
      class AnnotateTool < MCP::Tool
        description "Runs text through the SFL two-pass annotation pipeline " \
          "(spaCy grounding + LLM annotation) and returns the ideational and " \
          "interpersonal payloads for each clause, with annotation-source provenance."
        input_schema(
          properties: { text: { type: "string" } },
          required: ["text"]
        )

        class << self
          def call(text:, server_context:)
            document_id = "mcp-#{SecureRandom.uuid}"
            server_context.pipeline.compile(text, document_id:, store: false, embed: false, resume: false)
              .either(
                ->(clauses) { text_response(clauses.map { |c| Core::Wire.dump(c) }.to_json) },
                ->(failure) { MCP::Tool::Response.new([{ type: "text", text: "annotate failed: #{failure.inspect}" }],
                  is_error: true) }
              )
          end

          private def text_response(text)
            MCP::Tool::Response.new([{ type: "text", text: }])
          end
        end
      end

      # tools/call "retrieve_stance_filtered" -- wraps PgHybridRetriever,
      # applying interpersonal-payload filters (mood, modality/tenor range,
      # process_type, source_type) before ranking. This is the "Rhetorical
      # Firewall" piece phantom-agent never wired up: sfl_metadata was
      # written per-chunk but nothing filtered retrieval by it (see the
      # spec's Problem section).
      class RetrieveStanceFilteredTool < MCP::Tool
        description "Retrieves ranked clauses for a query, filtered by interpersonal " \
          "(stance) metadata -- mood, modality/tenor range, process type, source type -- " \
          "before the results reach an LLM."
        input_schema(
          properties: {
            query: { type: "string" },
            limit: { type: "integer" },
            filters: {
              type: "object",
              properties: {
                mood: { type: "string" },
                process_type: { type: "string" },
                source_type: { type: "string" },
                min_modality: { type: "number" },
                max_modality: { type: "number" },
                min_tenor: { type: "number" },
                max_tenor: { type: "number" },
              },
            },
          },
          required: ["query"]
        )

        class << self
          def call(query:, server_context:, limit: 10, filters: {})
            retrieval_filters = Core::Types::RetrievalFilters.new(**filters.transform_keys(&:to_sym).compact)
            results = server_context.retriever.retrieve(
              Core::Types::RetrievalQuery.new(query:, limit:, filters: retrieval_filters)
            )
            MCP::Tool::Response.new([{ type: "text", text: results.map { |r| Core::Wire.dump(r) }.to_json }])
          end
        end
      end

      def self.build(pipeline:, retriever:)
        server = MCP::Server.new(
          name: "sfl-substrate",
          tools: [AnnotateTool, RetrieveStanceFilteredTool],
          server_context: ToolContext.new(pipeline:, retriever:)
        )
        MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true, enable_json_response: true)
      end
    end
  end
end
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bundle exec rspec spec/api/mcp_server_spec.rb`
Expected: all examples pass.

- [ ] **Step 6: Wire `mcp_transport` into `Context`**

In `lib/sfl/api/context.rb`, add `:mcp_transport` to the `Struct.new` field list (line 26-30):

```ruby
    Context = Struct.new(
      :pipeline, :retriever, :synthesizer, :clause_store, :review_queue_repo,
      :annotation_review_repo, :pass_two, :clause_review_service, :mcp_transport,
      keyword_init: true
    )
```

Then in `Context.build` (around line 57-80), build `mcp_transport` from the already-local `pipeline` and a `retriever` local variable (currently `retriever:` is constructed inline twice — once for the `Context`'s own `retriever:` field, once inside `synthesizer:`'s `ContextSynthesizer.new`; pull it into a local so `mcp_transport` can share it too, rather than building a third instance):

```ruby
      def self.build(boot_result)
        logger, instrumenter, breaker = CLI.build_collaborators
        pipeline = CLI.build_pipeline(boot_result, { store: true, resume: false }, breaker:, instrumenter:, logger:)
        pass_two = LLM::EngineBuilder.call(
          config: boot_result.llm_config, lm_factory: boot_result.lm_factory, breaker:, instrumenter:, logger:
        )
        clause_store = Store::PgClauseStore.new(boot_result.db)
        annotation_review_repo = Store::PgAnnotationReviewRepository.new(boot_result.db)
        retriever = Store::PgHybridRetriever.new(db: boot_result.db, embedder: boot_result.embedder)

        new(
          pipeline:,
          retriever:,
          synthesizer: Retrieval::ContextSynthesizer.new(
            retriever:,
            lm: boot_result.lm_factory.for(:context_synthesis), breaker:, instrumenter:, logger:
          ),
          clause_store:,
          review_queue_repo: Store::PgReviewQueueRepository.new(boot_result.db),
          annotation_review_repo:,
          pass_two:,
          clause_review_service: ClauseReviewService.new(db: boot_result.db, clause_store:, annotation_review_repo:,
            pass_two:),
          mcp_transport: McpServer.build(pipeline:, retriever:)
        )
      end
```

- [ ] **Step 7: Uncomment the `/mcp` mount in `Server#build_roda_app`**

In `lib/sfl/api/server.rb` (from Task 1), uncomment (or add, if you skipped it in Task 1) the block:

```ruby
            r.on "mcp" do
              r.run outer.ctx.mcp_transport
            end
```

- [ ] **Step 8: Run the full server spec suite plus the new MCP spec**

Run: `bundle exec rspec spec/api/server_spec.rb spec/api/mcp_server_spec.rb`
Expected: all pass. `server_spec.rb`'s `ctx` fixture builds `SFL::API::Context.new(...)` directly (not via `.build`), so it does not need an `mcp_transport:` field passed for its own routes to keep working — but if any example exercises `/mcp/*`, add `mcp_transport: instance_double(MCP::Server::Transports::StreamableHTTPTransport)` to that spec's `ctx` `let` block.

- [ ] **Step 9: Run full verification and commit**

Run: `bundle exec rake`

```bash
git add Gemfile Gemfile.lock lib/sfl/api/mcp_server.rb lib/sfl/api/context.rb lib/sfl/api/server.rb \
  spec/api/mcp_server_spec.rb AGENTS.md
git commit -m "$(cat <<'EOF'
feat(api): add remote MCP server sharing the HTTP API's pipeline/retriever

annotate and retrieve_stance_filtered tools, served over Streamable HTTP
under /mcp in the same Roda tree the HTTP routes use -- no second process,
no internal HTTP hop. retrieve_stance_filtered is the "Rhetorical Firewall"
piece phantom-agent's sfl_metadata column was written for but never wired
up to filter retrieval.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NQUGhhhsJVnR2x7hkJ2V8R
EOF
)"
```

---

## Task 3: Podman Quadlet deployment

**Files:**
- Create: `deploy/quadlet/sfl-pgdata.volume`
- Create: `deploy/quadlet/sfl.network`
- Create: `deploy/quadlet/sfl-postgres.container`
- Create: `deploy/quadlet/sfl-api.container`
- Create: `deploy/quadlet/sfl-migrate.container`
- Modify: `AGENTS.md` (add a "Quadlet deployment" subsection under Developer Commands)

**Interfaces:**
- Consumes: `docker/api.Dockerfile` (unchanged — the combined Ruby+spaCy image these units run), `db/migrations/*` (via `bundle exec rake db:migrate`, run as the one-shot `sfl-migrate.container`).
- Produces: four systemd-managed units a fresh install activates with `systemctl --user daemon-reload && systemctl --user start sfl-api.service`. Nothing else in this plan depends on these files — they are the "spec Component 3" deliverable.

No Ruby code in this task — Quadlet unit files are plain systemd unit syntax with Podman-specific sections (`[Container]`, `[Volume]`, `[Network]`), read by `podman-system-generator` into ordinary `.service` units at boot. There is no existing template anywhere in this workspace to inherit from (confirmed during the design spec: neither `omega-13`'s `quadlets-spacy-whisper` branch nor `pop_os-workstation-builder`'s tracked "quadlet ecosystem" work landed actual unit files) — this is the first one, written directly from the Podman Quadlet spec.

- [ ] **Step 1: Create the named volume unit**

Create `deploy/quadlet/sfl-pgdata.volume`:

```ini
# Named volume for Postgres data, surviving container recreation (podman
# quadlet stops/starts sfl-postgres.container freely without losing data;
# only removing this volume unit does).
[Volume]
VolumeName=sfl-pgdata
```

- [ ] **Step 2: Create the network unit**

Create `deploy/quadlet/sfl.network`:

```ini
# Private network so sfl-postgres and sfl-api resolve each other by
# container name, mirroring docker-compose.yml's default bridge network.
[Network]
NetworkName=sfl
```

- [ ] **Step 3: Create the Postgres container unit**

Create `deploy/quadlet/sfl-postgres.container`:

```ini
[Unit]
Description=SFL Engine Postgres (pgvector)

[Container]
Image=docker.io/pgvector/pgvector:0.8.6-pg16
ContainerName=sfl-postgres
Network=sfl.network
Volume=sfl-pgdata.volume:/var/lib/postgresql/data
Environment=POSTGRES_USER=sfl
Environment=POSTGRES_PASSWORD=sfl
Environment=POSTGRES_DB=sfl_engine
# No PublishPort: only sfl-api (same sfl.network) needs to reach this
# container. Add PublishPort=127.0.0.1:5433:5432 if host-side psql access
# is wanted, matching docker-compose.yml's existing port choice.
HealthCmd=pg_isready -U sfl -d sfl_engine
HealthInterval=5s
HealthTimeout=5s
HealthRetries=10

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

- [ ] **Step 4: Create the one-shot migration container unit**

Create `deploy/quadlet/sfl-migrate.container`:

```ini
# One-shot: `systemctl --user start sfl-migrate.service` runs migrations and
# exits. Never part of sfl-api's own startup -- migrations are a deliberate,
# visible action here, same as this repo's existing "no auto-migration on
# boot" decision (AGENTS.md, SFL::Boot never migrates).
[Unit]
Description=SFL Engine database migration (one-shot)
Requires=sfl-postgres.service
After=sfl-postgres.service

[Container]
Image=localhost/sfl-api:latest
ContainerName=sfl-migrate
Network=sfl.network
Environment=DATABASE_URL=postgresql://sfl:sfl@sfl-postgres:5432/sfl_engine
Exec=bundle exec rake db:migrate

[Service]
Type=oneshot
RemainAfterExit=no
```

- [ ] **Step 5: Create the API container unit**

Create `deploy/quadlet/sfl-api.container`:

```ini
[Unit]
Description=SFL Engine API (HTTP + remote MCP)
Requires=sfl-postgres.service
After=sfl-postgres.service

[Container]
Image=localhost/sfl-api:latest
ContainerName=sfl-api
Network=sfl.network
Environment=DATABASE_URL=postgresql://sfl:sfl@sfl-postgres:5432/sfl_engine
Environment=HOST=0.0.0.0
Environment=PORT=3001
Environment=SFL_AUTO_START_DOCKER=0
PublishPort=127.0.0.1:3001:3001
HealthCmd=ruby -rnet/http -e "exit(Net::HTTP.get_response(URI('http://localhost:3001/health')).code == '200' ? 0 : 1)"
HealthInterval=10s
HealthTimeout=5s
HealthRetries=10

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

Note: `Image=localhost/sfl-api:latest` assumes the image is built locally first — `podman build -t localhost/sfl-api:latest -f docker/api.Dockerfile .` from the repo root, since these Quadlet units don't do a `build:` step the way `docker-compose.yml` does (Quadlets run pre-built images; building is a separate, explicit step, consistent with this repo's existing preference for explicit over implicit actions).

- [ ] **Step 6: Document the fresh-install flow in AGENTS.md**

Add a new subsection to `AGENTS.md`, after the existing "Database" block in Developer Commands (around line 46):

```markdown
# Podman Quadlet deployment (systemd-managed, alternative to docker-compose.yml)
podman build -t localhost/sfl-api:latest -f docker/api.Dockerfile .
mkdir -p ~/.config/containers/systemd
cp deploy/quadlet/*.{volume,network,container} ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start sfl-postgres.service
systemctl --user start sfl-migrate.service   # one-shot; re-run after any new migration
systemctl --user start sfl-api.service
```

- [ ] **Step 7: Commit**

```bash
git add deploy/quadlet AGENTS.md
git commit -m "$(cat <<'EOF'
feat(deploy): add Podman Quadlet units for sfl-postgres and sfl-api

First Quadlet template in this workspace -- no prior art to inherit from
(checked omega-13's quadlets-spacy-whisper branch and
pop_os-workstation-builder's quadlet-ecosystem work; neither landed actual
unit files). Migrations stay an explicit one-shot unit, never automatic,
consistent with SFL::Boot's existing "never migrates" contract.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NQUGhhhsJVnR2x7hkJ2V8R
EOF
)"
```

---

## Task 4: phantom-agent SFL API HTTP client

**Files:**
- Create: `src/phantom_agent/sfl_client.py`
- Modify: `src/phantom_agent/core/settings.py` (add `SFL_API_URL`)
- Modify: `pyproject.toml` (add `httpx` dependency)
- Test: `tests/test_sfl_client.py` (new)

**Interfaces:**
- Consumes: `SFL_API_URL` env var (default `http://localhost:3001`), the sfl-api `POST /pipeline/compile` endpoint from Task 1 (`{text:, document_id?:, store?:, embed?:} -> AnnotatedClause[]`).
- Produces: `phantom_agent.sfl_client.compile_chunk(text: str, *, document_id: str | None = None, store: bool = False, embed: bool = False, base_url: str | None = None, timeout: float = 30.0) -> list[dict] | None`. Returns `None` on any request/HTTP failure (matching `annotate_chunk`'s existing "return `None`, let the caller log and skip" contract, so Task 5's callers need minimal changes) and logs the failure via the `phantom_agent.sfl_client` logger. Raises nothing to the caller.

This module has no dependency on `phantom_agent.annotator` — it is written and tested standalone before Task 5 deletes that package and rewires its callers onto this client.

- [ ] **Step 1: Add the `httpx` dependency**

In `pyproject.toml`'s `dependencies` list (after `"huggingface-hub>=0.36.2",`), add:

```toml
    "httpx>=0.27",
```

Run: `uv sync`
Expected: `uv.lock` updates with `httpx` and its transitive deps (`httpcore`, `anyio`, `certifi`, etc.); no other package versions change.

- [ ] **Step 2: Add `SFL_API_URL` to settings**

In `src/phantom_agent/core/settings.py`, after the `DB_PARAMS` block (line 12), add:

```python
# Base URL of the sfl-engine HTTP API (shared-annotation-substrate spec).
# Trailing slash stripped so sfl_client.py's f"{SFL_API_URL}/pipeline/compile"
# never produces a double slash.
SFL_API_URL = os.getenv("SFL_API_URL", "http://localhost:3001").rstrip("/")
```

- [ ] **Step 3: Write the failing test**

Create `tests/test_sfl_client.py`:

```python
"""No test in this suite performs network I/O (see conftest.py's own
convention) -- httpx.MockTransport intercepts every request here instead."""
import httpx
import pytest

from phantom_agent import sfl_client


def _client_with(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_compile_chunk_returns_annotated_clauses_on_success():
    def handler(request):
        assert request.url.path == "/pipeline/compile"
        body = httpx.Request.read(request) and request.content
        import json
        payload = json.loads(body)
        assert payload["text"] == "hello"
        return httpx.Response(200, json=[{"id": "c-1", "text": "hello"}])

    result = sfl_client.compile_chunk("hello", client=_client_with(handler))

    assert result == [{"id": "c-1", "text": "hello"}]


def test_compile_chunk_returns_none_on_http_error():
    def handler(request):
        return httpx.Response(500, json={"error": "Internal Server Error", "request_id": "abc"})

    result = sfl_client.compile_chunk("hello", client=_client_with(handler))

    assert result is None


def test_compile_chunk_returns_none_on_connection_failure():
    def handler(request):
        raise httpx.ConnectError("connection refused", request=request)

    result = sfl_client.compile_chunk("hello", client=_client_with(handler))

    assert result is None


def test_compile_chunk_sends_document_id_store_and_embed_flags():
    captured = {}

    def handler(request):
        import json
        captured.update(json.loads(request.content))
        return httpx.Response(200, json=[])

    sfl_client.compile_chunk(
        "hello", document_id="doc-1", store=True, embed=True, client=_client_with(handler)
    )

    assert captured == {"text": "hello", "document_id": "doc-1", "store": True, "embed": True}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `pytest tests/test_sfl_client.py -v`
Expected: `ModuleNotFoundError: No module named 'phantom_agent.sfl_client'`.

- [ ] **Step 5: Implement `sfl_client.py`**

Create `src/phantom_agent/sfl_client.py`:

```python
"""HTTP client for the sfl-engine annotation/retrieval substrate.

Replaces phantom_agent.annotator's single-LLM-call SFL annotation
(retired -- see docs on the shared-annotation-substrate spec) with a thin
call to the sfl-engine HTTP API's POST /pipeline/compile, which runs the
real two-pass pipeline (spaCy grounding + LLM annotation, mood
canonicalization, tenor/modality_weight, annotation_source provenance).
"""
import logging

import httpx

from phantom_agent.core.settings import SFL_API_URL

logger = logging.getLogger("phantom_agent.sfl_client")


def compile_chunk(
    text: str,
    *,
    document_id: str | None = None,
    store: bool = False,
    embed: bool = False,
    base_url: str | None = None,
    timeout: float = 30.0,
    client: httpx.Client | None = None,
) -> list[dict] | None:
    """Sends `text` to the substrate's POST /pipeline/compile and returns the
    annotated clauses as a list of dicts, or None on any failure.

    Mirrors the old `annotate_chunk`'s "return None, let the caller log and
    skip" contract so existing callers need minimal changes: the substrate is
    now a network dependency, and a caller that wants stricter behavior
    (retry, queue-for-later) builds it on top of this function rather than
    this function guessing what every caller wants.

    `client` is an injection seam for tests (httpx.MockTransport) -- callers
    in production code never pass it, letting each call open and close its
    own short-lived httpx.Client.
    """
    body = {"text": text}
    if document_id is not None:
        body["document_id"] = document_id
    if store:
        body["store"] = store
    if embed:
        body["embed"] = embed

    owns_client = client is None
    http_client = client or httpx.Client(base_url=base_url or SFL_API_URL, timeout=timeout)
    try:
        response = http_client.post("/pipeline/compile", json=body)
        response.raise_for_status()
        return response.json()
    except httpx.HTTPStatusError as e:
        logger.error("sfl-api returned %s: %s", e.response.status_code, e.response.text)
        return None
    except httpx.HTTPError as e:
        logger.error("sfl-api request failed: %s", e)
        return None
    finally:
        if owns_client:
            http_client.close()
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `pytest tests/test_sfl_client.py -v`
Expected: all 4 tests pass.

- [ ] **Step 7: Commit**

```bash
git add pyproject.toml uv.lock src/phantom_agent/core/settings.py src/phantom_agent/sfl_client.py tests/test_sfl_client.py
git commit -m "$(cat <<'EOF'
feat(client): add HTTP client for the sfl-engine annotation substrate

compile_chunk() calls sfl-api's POST /pipeline/compile and returns None on
any failure, matching the old annotate_chunk() contract so its two callers
(cli.py's annotate-sfl, the annotation_stream TUI) need minimal rewiring
in the next task. Not yet wired to any caller.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NQUGhhhsJVnR2x7hkJ2V8R
EOF
)"
```

---

## Task 5: Retire phantom-agent's annotator, rewire callers to the client

**Files:**
- Delete: `src/phantom_agent/annotator/` (entire directory: `__init__.py`, `extractor.py`, `models.py`, `sfl_annotation.py`, `README.md`)
- Modify: `src/phantom_agent/cli.py:137-139`
- Modify: `src/ui/annotation_stream/app.py` (imports, `run()`, `_annotate_with_spinner()`, `_record()`)
- Test: `tests/test_cli_annotate_sfl.py` (new)

**Interfaces:**
- Consumes: `phantom_agent.sfl_client.compile_chunk` (Task 4).
- Produces: nothing new — this task removes a public module (`phantom_agent.annotator`) and its two call sites, replacing them with calls to the Task 4 client. No other code in this repo imports from `phantom_agent.annotator` (confirmed by grep during planning — the only importers are `cli.py:138` and `ui/annotation_stream/app.py:15-16`).

`run_sfl_annotation`'s batch-annotation loop and the `AnnotationStreamApp`'s per-chunk loop both currently: read `child_chunks` rows where `sfl_metadata IS NULL`, call the old annotator, write the result back into `sfl_metadata`. That storage shape (a JSONB blob per chunk, written but never read elsewhere — this is literally the dead-retrieval problem the spec's Problem section names) is unchanged by this task; only what produces the JSON changes, from the local single-LLM-call annotator to the substrate's real annotation. `sfl_metadata` now holds the substrate's actual `AnnotatedClause[]` shape (ideational + interpersonal payloads, mood/tenor/modality_weight/annotation_source) instead of the old flat `ChunkAnnotation` shape — anything downstream that ever starts reading `sfl_metadata` needs to expect the new shape, but nothing in this repo currently reads it (that's Future Work item #1's territory, not this plan's).

- [ ] **Step 1: Rewrite `cli.py`'s `annotate-sfl` non-TUI branch**

In `src/phantom_agent/cli.py`, replace lines 137-139:

```python
        else:
            from phantom_agent.annotator import run_sfl_annotation
            run_sfl_annotation(limit=args.limit)
```

with:

```python
        else:
            from phantom_agent.sfl_annotate import run_sfl_annotation
            run_sfl_annotation(limit=args.limit)
```

This points at a new, small replacement module (not `phantom_agent.annotator`, which is being deleted) that keeps the exact same `run_sfl_annotation(limit=10)` batch-loop shape `sfl_annotation.py` had, but calls `sfl_client.compile_chunk` instead of the old `annotate_chunk`. Create `src/phantom_agent/sfl_annotate.py`:

```python
"""Batch SFL annotation of unannotated chunks in the database, via the
sfl-engine substrate (replaces the retired phantom_agent.annotator)."""

import logging

import psycopg

from phantom_agent.sfl_client import compile_chunk

logger = logging.getLogger("phantom_agent.sfl_annotate")


def init_db_schema(conn):
    with conn.cursor() as cur:
        cur.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM information_schema.columns
                    WHERE table_name='child_chunks' AND column_name='sfl_metadata'
                ) THEN
                    ALTER TABLE child_chunks ADD COLUMN sfl_metadata JSONB;
                END IF;
            END
            $$;
        """)
    conn.commit()


def run_sfl_annotation(limit=10):
    from phantom_agent.core.settings import DB_PARAMS

    try:
        conn = psycopg.connect(**DB_PARAMS)
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return

    init_db_schema(conn)

    with conn.cursor() as cur:
        cur.execute("SELECT id, content FROM child_chunks WHERE sfl_metadata IS NULL LIMIT %s", (limit,))
        rows = cur.fetchall()

    logger.info(f"Found {len(rows)} chunks to annotate.")

    for chunk_id, content in rows:
        logger.info(f"Annotating chunk ID {chunk_id} ({len(content)} chars)...")
        clauses = compile_chunk(content, document_id=f"chunk-{chunk_id}")

        if clauses is not None:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE child_chunks SET sfl_metadata = %s WHERE id = %s",
                    (psycopg.types.json.Json(clauses), chunk_id),
                )
            conn.commit()
            logger.info(f"Successfully annotated and saved chunk {chunk_id}.")
        else:
            logger.warning(f"Skipping chunk {chunk_id} due to annotation failure.")

    conn.close()
```

- [ ] **Step 2: Write the failing test for the rewired CLI path**

Create `tests/test_cli_annotate_sfl.py`:

```python
"""Confirms `phantom-agent annotate-sfl` (non-TUI) calls the sfl-engine
substrate client, not the retired local annotator, and writes its result
back into sfl_metadata. No network or database I/O -- psycopg and
sfl_client.compile_chunk are both faked."""
from unittest.mock import MagicMock, patch

from phantom_agent import sfl_annotate


def test_run_sfl_annotation_calls_substrate_client_and_writes_result():
    fake_conn = MagicMock()
    fake_cursor = fake_conn.cursor.return_value.__enter__.return_value
    fake_cursor.fetchall.return_value = [(1, "The system processed it.")]

    with (
        patch("phantom_agent.sfl_annotate.psycopg.connect", return_value=fake_conn),
        patch("phantom_agent.sfl_annotate.compile_chunk", return_value=[{"id": "c-1"}]) as mock_compile,
    ):
        sfl_annotate.run_sfl_annotation(limit=5)

    mock_compile.assert_called_once_with("The system processed it.", document_id="chunk-1")
    update_calls = [c for c in fake_cursor.execute.call_args_list if "UPDATE child_chunks" in c.args[0]]
    assert len(update_calls) == 1


def test_run_sfl_annotation_skips_chunk_on_substrate_failure():
    fake_conn = MagicMock()
    fake_cursor = fake_conn.cursor.return_value.__enter__.return_value
    fake_cursor.fetchall.return_value = [(1, "The system processed it.")]

    with (
        patch("phantom_agent.sfl_annotate.psycopg.connect", return_value=fake_conn),
        patch("phantom_agent.sfl_annotate.compile_chunk", return_value=None),
    ):
        sfl_annotate.run_sfl_annotation(limit=5)

    update_calls = [c for c in fake_cursor.execute.call_args_list if "UPDATE child_chunks" in c.args[0]]
    assert len(update_calls) == 0
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pytest tests/test_cli_annotate_sfl.py -v`
Expected: `ModuleNotFoundError: No module named 'phantom_agent.sfl_annotate'` (module from Step 1 not yet created — create it now if you haven't).

- [ ] **Step 4: Run the test to verify it passes**

Run: `pytest tests/test_cli_annotate_sfl.py -v`
Expected: both tests pass.

- [ ] **Step 5: Rewire the `annotation_stream` TUI**

In `src/ui/annotation_stream/app.py`, replace the import block (lines 15-17):

```python
from phantom_agent.annotator.extractor import annotate_chunk
from phantom_agent.annotator.sfl_annotation import init_db_schema
from phantom_agent.core.settings import DB_PARAMS
```

with:

```python
from phantom_agent.sfl_client import compile_chunk
from phantom_agent.sfl_annotate import init_db_schema
from phantom_agent.core.settings import DB_PARAMS
```

Replace the `_LastErrorHandler`'s docstring reference (line 33-36, cosmetic — it references `annotate_chunk`'s own except-block, which the client's `compile_chunk` still has, just under a different logger name) and the handler's target logger. In `run()` (line 99), replace:

```python
        extractor_logger = logging.getLogger("sfl_annotator.extractor")
```

with:

```python
        extractor_logger = logging.getLogger("phantom_agent.sfl_client")
```

In `_annotate_with_spinner` (line 127-137), replace the `worker` closure's body:

```python
        def worker():
            result["annotation"] = annotate_chunk(content)
```

with:

```python
        def worker():
            result["annotation"] = compile_chunk(content, document_id=f"chunk-{chunk_id}")
```

In `_record` (lines 155-192), the method currently assumes `annotation` is the old `ChunkAnnotation` pydantic object (`annotation.model_dump_json()`, `annotation.clauses`, `annotation.dominant_process_type`, `annotation.dominant_mood`). The substrate returns a plain `list[dict]` of `AnnotatedClause` (one per clause, each with `interpersonal.mood`/`ideational.process_type`/`interpersonal.reasoning`, no single "dominant" summary across the whole chunk). Replace the whole method:

```python
    def _record(self, conn, chunk_id: int, content: str, clauses: list[dict] | None) -> None:
        snippet = content[:SNIPPET_LEN].replace("\n", " ")
        if clauses is None:
            self.failed += 1
            error = self._error_handler.last_message
            self._error_handler.last_message = None
            self.feed.append(FeedEntry(chunk_id, snippet, failed=True, error=error))
            return

        with conn.cursor() as cur:
            cur.execute(
                "UPDATE child_chunks SET sfl_metadata = %s WHERE id = %s",
                (psycopg.types.json.Json(clauses), chunk_id),
            )
        conn.commit()
        self.annotated += 1

        first_clause = None
        dominant_process_type = None
        dominant_mood = None
        if clauses:
            first = clauses[0]
            dominant_process_type = first["ideational"]["process_type"]
            dominant_mood = first["interpersonal"]["mood"]
            first_clause = ClausePreview(
                topical_theme=first["text"],
                rheme="",
                participants=[p["text"] for p in first["ideational"]["participants"]],
                circumstances=[c["text"] for c in first["ideational"]["circumstances"]],
            )

        self.feed.append(FeedEntry(
            chunk_id, snippet,
            dominant_process_type=dominant_process_type,
            dominant_mood=dominant_mood,
            confidence=None,
            clause_count=len(clauses),
            first_clause=first_clause,
        ))
```

`confidence=None` and the removed `_normalize_confidence` call: the old `ChunkAnnotation.clauses[*].confidence` field has no equivalent in the substrate's `AnnotatedClause` (the substrate's confidence signal is the `untrusted` boolean plus `annotation_source`, not a 0-1 float) — pass `None` through rather than inventing a number; check `render_stats`/`render_feed` in `stats.py`/`feed.py` handle a `None` confidence already (both are Rich renderers reading `FeedEntry.confidence`, which was already `Optional[float]` before this change per `_record`'s original `avg_confidence = ... if confidences else None`, so this is not a new code path for them).

Delete the now-unused `_normalize_confidence` function (lines 230-236) and its now-unused `import` (none — it only used builtins).

- [ ] **Step 6: Run the TUI's existing tests (if any) plus a manual smoke check**

Run: `pytest tests -k annotation_stream -v`
Expected: passes (there is currently no dedicated `annotation_stream` test file per the repo's `tests/` listing — if none run, that's expected; this step exists to catch one if it's been added since planning).

Manually verify the TUI still boots against a stubbed substrate:
Run: `SFL_API_URL=http://localhost:1 phantom-agent annotate-sfl --tui --limit 1`
Expected: the TUI starts, attempts one chunk, the `_annotate_with_spinner` thread's call fails fast (connection refused), the feed shows the chunk as failed rather than hanging — the client's `httpx.HTTPError` catch plus the existing `timeout=30.0` default is what prevents another `annotate-sfl --tui` hard-lock (the exact class of bug the repo's own recent commit `fa171a1` fixed for the old LLM call — the same discipline carries over to the new HTTP call, since `compile_chunk`'s `timeout=` parameter defaults to a real bound, not `None`).

- [ ] **Step 7: Delete the retired `annotator` package**

```bash
git rm -r src/phantom_agent/annotator
```

- [ ] **Step 8: Run the full test suite**

Run: `pytest`
Expected: all pass, no `ModuleNotFoundError` referencing `phantom_agent.annotator` anywhere.

- [ ] **Step 9: Delegate the documentation sweep**

Per this repo's `CLAUDE.md` ("Documentation Updates ... ALWAYS delegated ... Applies to any change that alters a public API, module path, package layout"), dispatch one subagent with `model: "haiku"` for the doc/`.omm` sweep this deletion requires. Give it:

- The diff: `git diff --stat HEAD` plus `codemap --diff` output from this task.
- Exact old → new paths: `src/phantom_agent/annotator/` (deleted, all four files) → `src/phantom_agent/sfl_client.py` (new, Task 4) and `src/phantom_agent/sfl_annotate.py` (new, this task).
- `.omm` nodes needing removal or retitling (found via `find .omm -path "*annotator*"` during planning): `.omm/overall-architecture/annotator/` (and its children `extractor/`, `models/`, `sfl-annotation/`), `.omm/overall-architecture/sfl-annotator/`, `.omm/overall-architecture/ingestion/sfl-annotator/`. Per `CLAUDE.md`'s ".omm is a node graph" rules: these represent a module that no longer exists (not a rename to a single new location, since the replacement is two smaller modules under different names) — the subagent should remove the retired nodes' directories, drop them from their parent's `children:` list and `diagram.mmd` edges, and add new nodes for `sfl_client` and `sfl_annotate` under whatever parent `annotator/` reported in its own `meta.yaml`'s `parentPath:`.
- `.omm/overall-architecture/ui/annotation-stream/` needs its `description.md`/`context.md` updated for the import change (still the same node — the TUI wasn't moved or renamed) — not a structural node change, a prose edit.
- Instruct it to sweep `README.md`, `docs/`, `.omm/`, `src/` for any other stale reference to `phantom_agent.annotator`, `annotate_chunk`, `ChunkAnnotation`, or `ClauseAnnotation`, and report anything it finds rather than leaving it.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(annotator): retire local SFL annotator, call the sfl-engine substrate

Deletes src/phantom_agent/annotator/ (single-LLM-call annotation with no
clause segmentation, mood canonicalization, tenor/modality_weight, or
annotation_source provenance). Both callers -- `annotate-sfl` and its --tui
mode -- now call phantom_agent.sfl_client.compile_chunk, which hits the
sfl-engine substrate's real two-pass pipeline over HTTP.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NQUGhhhsJVnR2x7hkJ2V8R
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** Component 1 (Roda) → Task 1. Component 2 (remote MCP) → Task 2. Component 3 (Quadlets) → Task 3. Component 4 (phantom-agent as client) → Tasks 4-5. Data Model's topic-keyed storage and the topic-identity-stability known-gap are unchanged by this plan (explicitly out of scope, per the spec) — no task touches `topics.id`. Future Work items 1-4 are all explicitly deferred by the spec and have no task here.
- **Type/interface consistency checked:** `Context#mcp_transport` (Task 2 Step 6) is read as `outer.ctx.mcp_transport` in `Server#build_roda_app` (Task 1 Step 3/Task 2 Step 7) — same name both places. `sfl_client.compile_chunk`'s signature (Task 4 Step 5) matches every call site in Task 5 (`compile_chunk(content, document_id:)` in both `sfl_annotate.py` and the TUI's `worker` closure).
- **A real gap found and closed during planning, not in the original spec text:** the spec's Component 4 named `extractor.py`/`models.py`/`sfl_annotation.py` as the files to retire, but a live grep found a fourth, more recently touched caller — `src/ui/annotation_stream/app.py` (the streaming TUI from this repo's own recent commits `4a3c8bb`/`cd2c183`/`fa171a1`) — which imports `annotate_chunk` directly and has its own bespoke `_record` logic keyed to the old `ChunkAnnotation` shape. Task 5 rewires it explicitly (Step 5) rather than leaving it broken by Step 7's deletion.
