# frozen_string_literal: true

require "time"
require "securerandom"
require "timeout"
require "json"

module SFL
  module LLM
    # Pass 2 use case: maps syntactic structures onto SFL interpersonal
    # and textual metafunctions via an LLM. Implements Ports::Annotator so
    # the pipeline never depends on ruby_llm directly.
    #
    # Replaces the legacy DSPy-based PassTwoEngine (track decision 7):
    # no provider-fallback chain, no CognitiveGas/rolling-synthesis
    # machinery (that belonged to the quarantined GEB sprint jobs, which
    # track decision 12 explicitly drops) — one provider per Engine
    # instance, one Breaker around each call, truthful "fallback"
    # provenance on any rejection (Degradation), and contract rejection
    # instead of clamp01 scale-guessing (F6/D9): an out-of-range
    # modality_weight/tenor is a Dry::Struct::Error this class catches
    # and degrades from, never silently rescaled.
    # rubocop:disable Metrics/ClassLength -- Pass 2's contract-rejection/degradation logic
    # (interpersonal_from, textual_from, reasoning_trace_from, and their WARN wiring) is one
    # conceptual unit; Degradation/DerivationHash/ResponseSymbolizer/the schemas/the annotators
    # are already split into their own files, this is what's left after that split.
    class Engine
      include Core::Ports::Annotator

      # Bounded retry policy for Pass 2 provider calls.
      #
      # A transient provider-side failure (429, 5xx, socket timeout) is the
      # single most common way an entire batch becomes 0.5 placeholders: one
      # bad round trip, 134 defaulted clauses, exit 0. Retrying it a few times
      # with exponential backoff recovers the run instead. A non-retryable
      # failure (400/401/403/404, a schema/coercion rejection, a bug in this
      # codebase) is not transient — retrying it three times only triples the
      # latency before the same outcome, so it fails fast.
      MAX_ATTEMPTS = 3
      BASE_BACKOFF_SECONDS = 0.5
      RETRYABLE_HTTP_STATUSES = [408, 409, 425, 429, 500, 502, 503, 504].freeze
      RETRYABLE_ERRORS = [Timeout::Error, IOError, SystemCallError].freeze

      # A 429 is a capacity signal, not a blip: it gets a longer base, more
      # attempts, jitter, and honors the provider's Retry-After (capped).
      RATE_LIMIT_STATUS = 429
      RATE_LIMIT_BASE_BACKOFF_SECONDS = 2.0
      RATE_LIMIT_MAX_ATTEMPTS = 5
      RETRY_AFTER_CAP_SECONDS = 30.0
      DEFAULT_JITTER = -> (delay) { rand * delay * 0.25 }
      EVIDENCE_HEADER_PREFIXES = %w[x-ratelimit retry-after].freeze

      # Largest number of clauses sent in one Pass 2 request. 215 clauses with
      # POS/dependency strings measured ~39k input tokens (~180 per clause) and
      # exceeded a 32k context window; 40 keeps a request near 7-8k tokens.
      DEFAULT_BATCH_SIZE = 40
      # Cap on the provider error text appended to a logged batch error.
      PROVIDER_ERROR_MAX_CHARS = 300
      CAUSE_CHAIN_LIMIT = 10

      # Bugs in this codebase (a typo'd method, a wrong-arity call, a bad
      # constant) must never be laundered into a "provider failure" and
      # degraded from: they are not transient, there is nothing to retry, and
      # a placeholder annotation would hide them forever. Only operational
      # failures degrade.
      PROGRAMMER_ERRORS = [NameError, ArgumentError, TypeError, KeyError].freeze

      # rubocop:disable Metrics/ParameterLists -- six independently-injectable collaborators
      # (an annotator pair, and the three cross-cutting ports every Engine in this codebase
      # takes), each named for exactly what it replaces in a test double.
      def initialize(
        chat: nil,
        clause_annotator: nil,
        batch_clause_annotator: nil,
        breaker: Core::Ports::Null::Breaker.new,
        instrumenter: Core::Ports::Null::Instrumenter.new,
        logger: Core::Ports::Null::Logger.new,
        sleeper: Kernel.method(:sleep),
        provider: nil,
        model: nil,
        batch_size: DEFAULT_BATCH_SIZE,
        jitter: DEFAULT_JITTER
      )
        raise ArgumentError, "batch_size must be a positive Integer (got #{batch_size.inspect})" \
          unless batch_size.is_a?(Integer) && batch_size.positive?

        @clause_annotator = clause_annotator || (chat && Annotators::ClauseAnnotator.new(lm: chat, instrumenter:))
        @batch_clause_annotator = batch_clause_annotator || (chat && Annotators::BatchClauseAnnotator.new(lm: chat, instrumenter:))
        raise ArgumentError, "must provide chat: or explicit clause_annotator:/batch_clause_annotator:" \
          unless @clause_annotator && @batch_clause_annotator

        @breaker = breaker
        @instrumenter = instrumenter
        @logger = logger
        @sleeper = sleeper
        @provider = provider
        @model = model
        @batch_size = batch_size
        @jitter = jitter
      end
      # rubocop:enable Metrics/ParameterLists

      # @param clause [SFL::Core::Types::SyntacticClause]
      # @param ideational [SFL::Core::Types::IdeationalPayload]
      # @param context [Hash] optional :semantic_coherence_score
      # @return [SFL::Core::Types::AnnotationResult]
      def annotate(clause, ideational, context: {})
        logger.debug("pass_two started", clause_id: clause.id)
        started_at = now

        result = annotation_result_for(clause, fetch_single(clause, ideational, context))
        log_completion(clause, result, started_at)
        result
      rescue *PROGRAMMER_ERRORS
        raise
      rescue => e
        log_failure(clause, e)
        default_result(clause, "LLM call failed: #{e.class}: #{e.message}")
      end

      # @param pairs [Array<[SFL::Core::Types::SyntacticClause, SFL::Core::Types::IdeationalPayload]>]
      # @param context [Hash] optional :semantic_coherence_score, applied to every pair
      # @return [Array<SFL::Core::Types::AnnotationResult>] same order as pairs
      def annotate_batch(pairs, context: {})
        pairs.each_slice(batch_size).flat_map { |slice| annotate_slice(slice, context) }
      end

      attr_reader :clause_annotator, :batch_clause_annotator, :breaker, :instrumenter, :logger, :sleeper, :provider, :model,
        :batch_size, :jitter
      private :clause_annotator, :batch_clause_annotator, :breaker, :instrumenter, :logger, :sleeper, :provider, :model,
        :batch_size, :jitter

      # One bounded request: its own batch_id, log pair, and failure scope, so
      # a failing slice defaults only its own clauses. Indices passed to the
      # annotator are per-slice, which is what raw_by_index is keyed by here.
      private def annotate_slice(pairs, context)
        batch_id = SecureRandom.uuid
        started_at = now
        logger.info("pass_two batch started", batch_id:, size: pairs.size)
        raw_by_index, batch_error = instrumenter.instrument("pass_two.batch", clause_count: pairs.size, batch_id:) do
          fetch_batch(pairs, context)
        end

        missing = []
        results = pairs.each_with_index.map do |(clause, _ideational), index|
          instrumenter.instrument("pass_two.clause", clause_id: clause.id, batch_id:) do
            raw = raw_by_index[index]
            next annotation_result_for(clause, raw) if raw

            missing << index
            default_result(clause, missing_annotation_reason(index, batch_error))
          end
        end

        logger.info("pass_two batch finished", batch_id:, size: pairs.size, latency_ms: ((now - started_at) * 1000).round(2))
        log_batch_coverage(pairs, missing, batch_error, batch_id)
        results
      end

      private def fetch_single(clause, ideational, context)
        with_retries("pass_two.annotate") do
          instrumenter.instrument("pass_two.annotate", clause_id: clause.id) do
            breaker.call("pass_two.annotate") { clause_annotator.call(build_context(clause, ideational, context)) }
          end
        end
      end

      # Bounded exponential backoff. Only a retryable failure earns another
      # attempt; everything else propagates on the first one, so a 400 costs
      # one provider call rather than three. A 429 gets its own, longer policy.
      private def with_retries(label)
        attempt = 0
        begin
          attempt += 1
          yield
        rescue => e
          raise unless retryable?(e)

          evidence = retry_evidence(e)
          max_attempts = (evidence[:status] == RATE_LIMIT_STATUS) ? RATE_LIMIT_MAX_ATTEMPTS : MAX_ATTEMPTS
          if attempt >= max_attempts
            logger.warn("#{label} attempt failed, retries exhausted", attempt:, max_attempts:, error_class: e.class,
              error_message: e.message, **evidence)
            raise
          end

          delay = backoff_delay(attempt, evidence)
          logger.warn("#{label} attempt failed, retrying", attempt:, max_attempts:, delay_s: delay,
            error_class: e.class, error_message: e.message, **evidence)
          sleeper.call(delay)
          retry
        end
      end

      private def backoff_delay(attempt, evidence)
        return BASE_BACKOFF_SECONDS * (2 ** (attempt - 1)) unless evidence[:status] == RATE_LIMIT_STATUS

        computed = RATE_LIMIT_BASE_BACKOFF_SECONDS * (2 ** (attempt - 1))
        computed += jitter.call(computed)
        hinted = retry_after_seconds(evidence[:ratelimit_headers])
        hinted ? [hinted, computed].max.clamp(0, RETRY_AFTER_CAP_SECONDS).to_f : computed.to_f
      end

      # Diagnostic fields for a failed attempt: only the allow-listed
      # rate-limit headers and the provider name, never credentials or bodies.
      private def retry_evidence(error)
        headers = ratelimit_headers_for(error)
        {
          status: http_status_from(error),
          retry_after: headers["retry-after"],
          ratelimit_headers: headers,
          provider: provider_name_for(error),
        }
      end

      private def retryable?(error)
        return false if PROGRAMMER_ERRORS.any? { |klass| error.is_a?(klass) }
        return false if error.is_a?(Dry::Struct::Error)
        return false if error.is_a?(LLM::MalformedResponse)
        return true if RETRYABLE_ERRORS.any? { |klass| error.is_a?(klass) }

        status = http_status_from(error)
        status ? RETRYABLE_HTTP_STATUSES.include?(status) : false
      end

      # DSPy/ruby_llm adapter errors carry the provider status inside their
      # message ("OpenAI adapter error: {status: 400, ...}") rather than as a
      # typed attribute, so the status is read off #status when the error
      # exposes one and parsed out of the message otherwise. An error with no
      # recognizable status is treated as non-retryable: failing fast and
      # loudly is the correct default for an unclassifiable failure.
      private def http_status_from(error)
        return error.status.to_i if error.respond_to?(:status) && error.status

        message = error.message.to_s
        match = message.match(/status(?:_code)?['"]?\s*[:=>]+\s*['"]?(\d{3})/i) ||
          message.match(/\b(?:HTTP\s*)?([45]\d{2})\b/)
        match && match[1].to_i
      end

      # -- context-building (index/instrument/breaker) plus
      # index-keying the response is one pipeline step; splitting it further would scatter
      # a single request/response round trip across method boundaries.
      private def fetch_batch(pairs, context)
        contexts = pairs.each_with_index.map do |(clause, ideational), index|
          build_context(clause, ideational, context).merge(index:)
        end

        raw = with_retries("pass_two.annotate_batch") do
          instrumenter.instrument("pass_two.annotate_batch", clause_count: pairs.size) do
            breaker.call("pass_two.annotate_batch") { batch_clause_annotator.call(contexts) }
          end
        end
        [raw.to_h { |entry| [entry[:index], entry] }, nil]
      rescue *PROGRAMMER_ERRORS
        raise
      rescue => e
        [{}, e]
      end

      private def missing_annotation_reason(index, batch_error)
        return "No annotation returned for index #{index} — defaults applied" unless batch_error

        "Pass 2 batch call failed after #{MAX_ATTEMPTS} attempt(s) " \
          "(#{batch_error.class}: #{batch_error.message}) — defaults applied"
      end

      # The defect this replaces: a whole-batch provider failure logged one
      # WARN, returned {}, and 134 clauses silently became 0.5 placeholders in
      # a report that still exited 0. Coverage is now always stated, a total
      # failure is an ERROR rather than a WARN, and every defaulted clause
      # carries `annotation_source: "fallback"` — which SFL::CLI counts and
      # turns into a non-zero exit code.
      private def log_batch_coverage(pairs, missing, batch_error, batch_id)
        return if missing.empty?

        pct = (missing.size * 100.0 / pairs.size).round(1)
        message = "pass_two batch #{batch_id}: #{missing.size}/#{pairs.size} clauses (#{pct}%) defaulted"
        fields = { batch_id:, missing: missing.size, total: pairs.size, error_message: (format_error(batch_error) if batch_error) }

        if missing.size == pairs.size
          logger.error(message, **fields)
        else
          logger.warn(message, **fields, missing_indices: missing.take(20).join(","))
        end
      end
      # -- six independent Hash entries built from clause/
      # ideational data; each is a one-line map/join already extracted as far as it reasonably
      # goes (root_verb_for is the one that had real branching logic to pull out).
      private def build_context(clause, ideational, extra)
        {
          text: clause.text,
          root_verb: root_verb_for(clause),
          process_type: ideational.process_type,
          participants: ideational.participants.map { |p| "#{p.role}: #{p.text}" }.join(", "),
          pos_tags: clause.tokens.map { |t| "#{t.text}/#{t.pos}" }.join(" "),
          dependencies: clause.tokens.map { |t| "#{t.text}<#{t.dep}" }.join(" "),
          semantic_coherence_score: extra[:semantic_coherence_score],
        }
      end
      private def root_verb_for(clause)
        root = clause.tokens[clause.root_index]
        return "unknown" unless root

        "#{root.text} (lemma: #{root.lemma}, pos: #{root.pos}, tag: #{root.tag})"
      end

      private def annotation_result_for(clause, raw)
        interpersonal = interpersonal_from(clause, raw)
        textual = textual_from(clause, raw)

        Core::Types::AnnotationResult.new(
          interpersonal: interpersonal || Degradation.default_interpersonal(
            clause.id, reason: "Invalid interpersonal values — defaults applied"
          ),
          textual: textual || Degradation.default_textual(clause.id)
        )
      end

      # -- normalize + log + build a seven-attribute
      # struct is the same three-step shape textual_from uses; nothing left to extract that
      # conclusion_for/safe_reasoning_trace_from haven't already pulled out.
      private def interpersonal_from(clause, raw)
        raw_mood = coerce_to_string(raw[:mood])
        mood, status = Core::ClassificationRegistry.normalize(:mood, raw_mood)
        log_classification_gap(:mood, status, raw[:mood], mood, clause)
        conclusion = conclusion_for(mood, raw)

        Core::Types::InterpersonalPayload.new(
          clause_id: clause.id,
          mood:,
          modality_weight: raw[:modality_weight],
          tenor: raw[:tenor],
          speaker_attitude: coerce_to_string(raw[:speaker_attitude]),
          reasoning: coerce_to_string(raw[:reasoning]),
          annotation_source: "llm",
          raw_classification: raw_mood,
          classification_status: status.to_s,
          untrusted: status == :unknown,
          reasoning_trace: safe_reasoning_trace_from(raw, conclusion, clause)
        )
      rescue Dry::Struct::Error => e
        logger.warn("pass_two invalid interpersonal, defaults applied", clause_id: clause.id, error_message: e.message)
        nil
      end
      private def conclusion_for(mood, raw)
        {
          mood:,
          modality_weight: raw[:modality_weight],
          tenor: raw[:tenor],
          speaker_attitude: raw[:speaker_attitude],
        }
      end

      # A malformed reasoning trace must never default the clause's actual
      # mood/tenor/modality — those came back correctly from the LLM;
      # only the provenance layer is at risk. Guarded separately from
      # interpersonal_from so one bad premise can't default the whole
      # clause, only its reasoning_trace.
      private def safe_reasoning_trace_from(raw, conclusion, clause)
        reasoning_trace_from(raw, conclusion)
      rescue Dry::Struct::Error => e
        logger.warn("pass_two invalid reasoning_trace, left nil", clause_id: clause.id, error_message: e.message)
        nil
      end

      # -- one struct literal, six required attributes
      private def reasoning_trace_from(raw, conclusion)
        premises = (raw[:premises] || []).map do |p|
          Core::Types::Premise.new(type: p[:type], source: p[:source], value: p[:value], weight: p[:weight])
        end
        inference_rule = coerce_to_string(raw[:inference_rule] || "unknown")

        Core::Types::ReasoningTrace.new(
          premises:,
          inference_rule:,
          conclusion:,
          confidence: raw[:confidence] || 0.5,
          derivation_hash: DerivationHash.compute(premises:, inference_rule:, conclusion:),
          generated_at: Time.now
        )
      end
      # -- normalize + log + construct is
      # the same three-step shape as interpersonal_from; splitting it further than that
      # (already-extracted) shared shape would fragment one classification-then-build step.
      private def textual_from(clause, raw)
        raw_theme_type = coerce_to_string(raw[:theme_type])
        theme_type, status = Core::ClassificationRegistry.normalize(:theme_type, raw_theme_type)
        log_classification_gap(:theme_type, status, raw[:theme_type], theme_type, clause)

        Core::Types::TextualPayload.new(
          clause_id: clause.id,
          topical_theme: coerce_to_string(raw[:topical_theme] || clause.text.split.first),
          textual_theme: coerce_to_string(raw[:textual_theme]),
          interpersonal_theme: coerce_to_string(raw[:interpersonal_theme]),
          rheme: coerce_to_string(raw[:rheme]),
          theme_type:,
          raw_classification: raw_theme_type,
          classification_status: status.to_s,
          untrusted: status == :unknown
        )
      rescue Dry::Struct::Error => e
        logger.warn("pass_two invalid textual, defaults applied", clause_id: clause.id, error_message: e.message)
        nil
      end
      private def default_result(clause, reason)
        Core::Types::AnnotationResult.new(
          interpersonal: Degradation.default_interpersonal(clause.id, reason:),
          textual: Degradation.default_textual(clause.id)
        )
      end

      # Shared WARN wiring for both ClassificationRegistry dimensions
      # (mood in interpersonal_from, theme_type in textual_from).
      # :unknown means the value fell through to the default — a real
      # schema gap. :fuzzy means Jaro-Winkler resolved a near-miss to a
      # real category — the value is good, but it still gets surfaced so
      # the alias table can gain a permanent entry instead of paying the
      # fuzzy scan on every future run.
      private def log_classification_gap(dimension, status, raw_value, resolved, clause)
        return unless %i[unknown fuzzy].include?(status)

        hint = " (unrecognized value, consider adding it to ClassificationRegistry)" if status == :unknown
        logger.warn("pass_two #{status} #{dimension}#{hint}", clause_id: clause.id, dimension:, raw_value:, resolved:)
      end

      private def log_completion(clause, result, started_at)
        elapsed_ms = ((now - started_at) * 1000).round(2)
        interpersonal = result.interpersonal
        logger.info("pass_two completed", clause_id: clause.id, mood: interpersonal.mood, tenor: interpersonal.tenor,
          modality_weight: interpersonal.modality_weight, latency_ms: elapsed_ms, provider:, model:)
      end

      private def log_failure(clause, error)
        logger.error("pass_two failed", clause_id: clause.id, error_class: error.class, error_message: format_error(error))
      end

      private def format_error(error)
        detail = provider_error_detail(error)
        suffix = " | provider: #{detail}" if detail
        "#{error.class}: #{error.message}#{suffix}\n#{error.backtrace&.take(15)&.join("\n")}"
      end

      # The adapter error's own message omits the provider's reason; that sits
      # in #body of an underlying API error somewhere on the #cause chain.
      # Only the extracted message is returned, never headers or request data.
      private def provider_error_detail(error)
        cause_chain(error).each do |candidate|
          message = body_message(candidate.body) if candidate.respond_to?(:body)
          return message if message
        end
        nil
      rescue
        nil
      end

      private def cause_chain(error)
        chain = []
        candidate = error
        CAUSE_CHAIN_LIMIT.times do
          break unless candidate

          chain << candidate
          candidate = candidate.cause
        end
        chain
      end

      # Allow-listed rate-limit headers (lowercased name => String) from the
      # first error on the cause chain that responds to #headers; {} on any
      # odd shape. Everything else, notably Authorization, is dropped here.
      private def ratelimit_headers_for(error)
        holder = cause_chain(error).find { |candidate| candidate.respond_to?(:headers) }
        raw = holder&.headers
        return {} unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(name, value), kept|
          key = name.to_s.downcase
          kept[key] = value.to_s if EVIDENCE_HEADER_PREFIXES.any? { |prefix| key.start_with?(prefix) }
        end
      rescue
        {}
      end

      private def provider_name_for(error)
        cause_chain(error).each do |candidate|
          name = provider_name_in(candidate.body) if candidate.respond_to?(:body)
          return name if name
        end
        nil
      rescue
        nil
      end

      private def provider_name_in(body)
        error = body.is_a?(Hash) ? (body[:error] || body["error"]) : nil
        metadata = error.is_a?(Hash) ? (error[:metadata] || error["metadata"]) : nil
        name = metadata.is_a?(Hash) ? (metadata[:provider_name] || metadata["provider_name"]) : nil
        name.to_s if name.is_a?(String) && !name.empty?
      end

      # Seconds to wait per the provider, or nil when absent, unparseable or
      # negative. retry-after-ms is the more precise header, so it wins.
      private def retry_after_seconds(headers)
        milliseconds = numeric_seconds(headers["retry-after-ms"], 0.001)
        return milliseconds if milliseconds

        value = headers["retry-after"]
        numeric_seconds(value, 1) || http_date_seconds(value)
      end

      private def numeric_seconds(value, scale)
        value.to_f * scale if value.to_s.strip.match?(/\A\d+(?:\.\d+)?\z/)
      end

      private def http_date_seconds(value)
        seconds = Time.httpdate(value.to_s.strip) - Time.now
        seconds if seconds >= 0
      rescue ArgumentError
        nil
      end

      private def body_message(body)
        error = body.is_a?(Hash) ? (body[:error] || body["error"]) : nil
        return unless error.is_a?(Hash)

        text = raw_inner_message(error[:metadata] || error["metadata"]) || error[:message] || error["message"]
        text.to_s.strip[0, PROVIDER_ERROR_MAX_CHARS] if text.is_a?(String) && !text.strip.empty?
      end

      # OpenRouter nests the upstream provider's JSON as a string in metadata.raw.
      private def raw_inner_message(metadata)
        raw = metadata.is_a?(Hash) ? (metadata[:raw] || metadata["raw"]) : nil
        return unless raw.is_a?(String)

        inner = JSON.parse(raw)
        message = inner.dig("error", "message") if inner.is_a?(Hash) && inner["error"].is_a?(Hash)
        message if message.is_a?(String)
      rescue JSON::ParserError
        nil
      end

      private def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # LLMs sometimes return Arrays for String fields (e.g. ["declarative"]).
      # Coerce to a single String for downstream code that expects it.
      private def coerce_to_string(value)
        case value
        when Array then value.first.to_s
        else value.to_s
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
