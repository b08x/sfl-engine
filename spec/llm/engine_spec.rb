# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe SFL::LLM::Engine do
  let(:token) do
    SFL::Core::Types::SyntacticToken.new(
      text: "works", lemma: "work", pos: "VERB", tag: "VBZ",
      dep: "ROOT", head_index: -1, morphology: {}, index: 0
    )
  end
  let(:clause) do
    SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text: "It works.", tokens: [token], root_index: 0, sentence_index: 0, section_id: "doc-1"
    )
  end
  let(:ideational) do
    SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-1", process_type: "material",
      participants: [SFL::Core::Types::Participant.new(role: "Actor", text: "It")],
      circumstances: [], raw_transitivity: {}
    )
  end

  let(:valid_raw) do
    {
      mood: "declarative",
      modality_weight: 0.8,
      tenor: 0.6,
      speaker_attitude: "neutral",
      topical_theme: "It",
      textual_theme: nil,
      interpersonal_theme: nil,
      rheme: "works",
      theme_type: "unmarked",
      reasoning: "because",
      inference_rule: "default_declarative",
      confidence: 0.9,
      premises: [{ type: "pos", source: "works", value: "VERB", weight: 0.5 }],
    }
  end

  describe "#initialize" do
    it "raises ArgumentError when given neither chat: nor explicit annotators" do
      expect { described_class.new }.to raise_error(ArgumentError, /chat:/)
    end
  end

  describe "#annotate" do
    it "builds a full AnnotationResult with annotation_source llm and a derivation_hash on success" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("llm")
      expect(result.interpersonal.mood).to eq("declarative")
      expect(result.interpersonal.reasoning_trace.derivation_hash).to match(/\A[0-9a-f]{64}\z/)
      expect(result.textual.topical_theme).to eq("It")
    end

    it "passes a structured context Hash (not a formatted string) to the annotator" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator)
      allow(clause_annotator).to receive(:call).and_return(valid_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      engine.annotate(clause, ideational)

      expect(clause_annotator).to have_received(:call) do |context|
        expect(context).to include(text: "It works.", process_type: "material")
        expect(context[:root_verb]).to include("works")
      end
    end

    it "degrades to a truthful fallback when a value violates its Dry::Struct contract (F6/D9)" do
      clause_annotator = instance_double(
        SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(modality_weight: 5.0)
      )
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("fallback")
      expect(result.interpersonal.modality_weight).to eq(0.5)
    end

    it "resolves a fuzzy/aliased mood via ClassificationRegistry rather than rejecting it" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(mood: "question"))
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("llm")
      expect(result.interpersonal.mood).to eq("interrogative")
    end

    it "leaves interpersonal values intact when only the reasoning_trace's premises are malformed" do
      bad_premise_raw = valid_raw.merge(premises: [{ type: "pos", source: "x" }]) # missing required :value
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: bad_premise_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("llm")
      expect(result.interpersonal.mood).to eq("declarative")
      expect(result.interpersonal.reasoning_trace).to be_nil
    end

    it "degrades to a truthful fallback when the annotator raises" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator)
      allow(clause_annotator).to receive(:call).and_raise(StandardError, "network blew up")
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("fallback")
      expect(result.interpersonal.reasoning).to include("network blew up")
    end

    it "wraps the call in the injected Breaker" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw)
      breaker = instance_double(SFL::Core::Ports::TimeoutBreaker)
      allow(breaker).to receive(:call).and_yield
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, breaker:)

      engine.annotate(clause, ideational)

      expect(breaker).to have_received(:call).with("pass_two.annotate")
    end
  end

  describe "#annotate_batch" do
    it "degrades the batch to fallback, with no retry, when DSPy cannot decode the response (fact 3)" do
      dspy_error = TypeError.new("no implicit conversion of Float into Hash").tap do |error|
        error.set_backtrace(["/home/b08x/.rbenv/gems/dspy-0.34.0/lib/dspy/predict.rb:88:in 'call'"])
      end
      predictor = instance_double(DSPy::Predict, configure: nil)
      allow(DSPy::Predict).to receive(:new).and_return(predictor)
      allow(predictor).to receive(:call).and_raise(dspy_error)
      batch_clause_annotator = SFL::LLM::Annotators::BatchClauseAnnotator.new(lm: double)
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:, sleeper: -> (_) {})

      results = engine.annotate_batch([[clause, ideational]])

      expect(results.first.interpersonal.annotation_source).to eq("fallback")
      expect(predictor).to have_received(:call).once
    end

    it "does not render the cumulative timing report for every batch" do
      batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator, call: [])
      instrumenter = instance_spy(SFL::Core::Ports::TimingInstrumenter)
      allow(instrumenter).to receive(:instrument).and_yield
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:, instrumenter:)

      engine.annotate_batch([[clause, ideational]])

      expect(instrumenter).not_to have_received(:report_json)
    end

    it "returns [] for an empty pairs list without calling the batch annotator" do
      batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
      allow(batch_clause_annotator).to receive(:call)
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:)

      expect(engine.annotate_batch([])).to eq([])
      expect(batch_clause_annotator).not_to have_received(:call)
    end

    it "maps each raw annotation back to its clause by index, in input order" do
      clause2 = clause.new(id: "c-2", text: "It fails.")
      raw_results = [valid_raw.merge(index: 1, mood: "imperative"), valid_raw.merge(index: 0)]
      batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator, call: raw_results)
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:)

      results = engine.annotate_batch([[clause, ideational], [clause2, ideational]])

      expect(results[0].interpersonal.mood).to eq("declarative")
      expect(results[1].interpersonal.mood).to eq("imperative")
    end

    it "defaults any clause the LLM didn't return an annotation for" do
      clause2 = clause.new(id: "c-2", text: "Missing.")
      batch_clause_annotator = instance_double(
        SFL::LLM::Annotators::BatchClauseAnnotator, call: [valid_raw.merge(index: 0)]
      )
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:)

      results = engine.annotate_batch([[clause, ideational], [clause2, ideational]])

      expect(results[0].interpersonal.annotation_source).to eq("llm")
      expect(results[1].interpersonal.annotation_source).to eq("fallback")
    end

    # Replaces "defaults every clause when the batch call itself raises",
    # which asserted the defect as the contract: a single transient provider
    # error became a full report of 0.5 placeholders, logged at WARN, exit 0.
    # A batch failure must now be retried when it is transient, must fail fast
    # when it is not, and must never be invisible when it does default clauses.
    describe "batch failure handling" do
      let(:logger) { instance_spy(SFL::Core::Ports::JournaldLogger) }
      let(:sleeps) { [] }
      let(:sleeper) { -> (seconds) { sleeps << seconds } }

      def engine_with(batch_clause_annotator, **extra)
        described_class.new(clause_annotator: double, batch_clause_annotator:, logger:, sleeper:, **extra)
      end

      it "retries a transient provider failure with exponential backoff and defaults nothing on recovery" do
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        attempts = [
          -> { raise StandardError, "OpenAI adapter error: {status: 429, message: rate limited}" },
          -> { [valid_raw.merge(index: 0)] },
        ]
        allow(batch_clause_annotator).to receive(:call) { attempts.shift.call }

        results = engine_with(batch_clause_annotator, jitter: -> (_) { 0 }).annotate_batch([[clause, ideational]])

        expect(results[0].interpersonal.annotation_source).to eq("llm")
        expect(sleeps).to eq([SFL::LLM::Engine::RATE_LIMIT_BASE_BACKOFF_SECONDS])
        expect(logger).not_to have_received(:error)
      end

      it "warns on each retry with attempt, max_attempts and delay_s" do
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(batch_clause_annotator).to receive(:call).and_raise(Timeout::Error, "slow")

        engine_with(batch_clause_annotator).annotate_batch([[clause, ideational]])

        expect(logger).to have_received(:warn).with(
          a_string_including("pass_two.annotate_batch attempt failed"),
          hash_including(attempt: 1, max_attempts: SFL::LLM::Engine::MAX_ATTEMPTS, delay_s: 0.5)
        )
        expect(logger).to have_received(:warn).with(
          a_string_including("retrying"), hash_including(attempt: 2, delay_s: 1.0)
        )
      end

      it "logs batch start and finish at info with batch_id, size and latency_ms" do
        batch_clause_annotator = instance_double(
          SFL::LLM::Annotators::BatchClauseAnnotator, call: [valid_raw.merge(index: 0)]
        )

        engine_with(batch_clause_annotator).annotate_batch([[clause, ideational]])

        expect(logger).to have_received(:info).with(
          "pass_two batch started", batch_id: a_kind_of(String), size: 1
        )
        expect(logger).to have_received(:info).with(
          "pass_two batch finished", batch_id: a_kind_of(String), size: 1, latency_ms: a_kind_of(Numeric)
        )
      end

      it "retries a timeout up to MAX_ATTEMPTS, then defaults with the cause named in each clause's provenance" do
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(batch_clause_annotator).to receive(:call).and_raise(Timeout::Error, "annotate_batch exceeded 60s")

        results = engine_with(batch_clause_annotator).annotate_batch([[clause, ideational]])

        expect(batch_clause_annotator).to have_received(:call).exactly(SFL::LLM::Engine::MAX_ATTEMPTS).times
        expect(sleeps.size).to eq(SFL::LLM::Engine::MAX_ATTEMPTS - 1)
        expect(results[0].interpersonal.annotation_source).to eq("fallback")
        expect(results[0].interpersonal.reasoning).to include("Timeout::Error", "annotate_batch exceeded 60s")
      end

      it "fails fast on a non-retryable 400 instead of spending three provider calls on it" do
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(batch_clause_annotator).to receive(:call)
          .and_raise(StandardError, "OpenAI adapter error: {status: 400, message: unknown model}")

        engine_with(batch_clause_annotator).annotate_batch([[clause, ideational]])

        expect(batch_clause_annotator).to have_received(:call).once
        expect(sleeps).to be_empty
      end

      it "logs a total batch failure at ERROR with its coverage — never silently, never at WARN" do
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(batch_clause_annotator).to receive(:call)
          .and_raise(StandardError, "OpenAI adapter error: {status: 400, message: unknown model}")

        engine_with(batch_clause_annotator).annotate_batch([[clause, ideational], [clause, ideational]])

        expect(logger).to have_received(:error).with(
          a_string_including("2/2 clauses (100.0%) defaulted"),
          hash_including(missing: 2, total: 2, error_message: a_string_including("unknown model"))
        )
      end

      it "counts a partial provider response — the missing indices are logged, not invisible" do
        batch_clause_annotator = instance_double(
          SFL::LLM::Annotators::BatchClauseAnnotator, call: [valid_raw.merge(index: 0)]
        )

        engine_with(batch_clause_annotator).annotate_batch([[clause, ideational], [clause, ideational]])

        expect(logger).to have_received(:warn).with(
          a_string_including("1/2 clauses (50.0%) defaulted"), hash_including(missing: 1, missing_indices: "1")
        )
      end

      it "re-raises a bug in this codebase rather than laundering it into a fallback annotation" do
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(batch_clause_annotator).to receive(:call).and_raise(NoMethodError, "undefined method 'foo' for nil")

        expect { engine_with(batch_clause_annotator).annotate_batch([[clause, ideational]]) }
          .to raise_error(NoMethodError)
      end
    end

    describe "provider 429 handling" do
      let(:logger) { instance_spy(SFL::Core::Ports::JournaldLogger) }
      let(:sleeps) { [] }
      let(:sleeper) { -> (seconds) { sleeps << seconds } }
      let(:no_jitter) { -> (_) { 0 } }
      let(:batch_clause_annotator) { instance_double(SFL::LLM::Annotators::BatchClauseAnnotator) }
      let(:http_error_class) do
        Class.new(StandardError) do
          attr_reader :status, :headers, :body

          def initialize(status:, headers: nil, body: nil, message: "Provider returned error")
            super(message)
            @status = status
            @headers = headers
            @body = body
          end
        end
      end

      def http_error(status = 429, **)
        http_error_class.new(status:, **)
      end

      def run_with(error, jitter: no_jitter)
        allow(batch_clause_annotator).to receive(:call).and_raise(error)
        engine = described_class.new(clause_annotator: double, batch_clause_annotator:, logger:, sleeper:, jitter:)
        engine.annotate_batch([[clause, ideational]])
      end

      it "backs off 2, 4, 8, 16 seconds over 5 attempts for a 429 without Retry-After, then defaults" do
        results = run_with(http_error)

        expect(sleeps).to eq([2.0, 4.0, 8.0, 16.0])
        expect(batch_clause_annotator).to have_received(:call).exactly(5).times
        expect(results[0].interpersonal.annotation_source).to eq("fallback")
      end

      it "adds the injected jitter to the computed delay" do
        seen = []
        run_with(http_error, jitter: -> (delay) { seen << delay; delay * 0.25 })

        expect(seen).to eq([2.0, 4.0, 8.0, 16.0])
        expect(sleeps).to eq([2.5, 5.0, 10.0, 20.0])
      end

      it "uses a default jitter of up to 25 percent" do
        allow(batch_clause_annotator).to receive(:call).and_raise(http_error)
        described_class.new(clause_annotator: double, batch_clause_annotator:, logger:, sleeper:)
          .annotate_batch([[clause, ideational]])

        expect(sleeps.zip([2.0, 4.0, 8.0, 16.0])).to all(satisfy { |slept, base| slept.between?(base, base * 1.25) })
        expect(sleeps.size).to eq(4)
      end

      it "sleeps for Retry-After seconds when that exceeds the computed delay" do
        run_with(http_error(headers: { "Retry-After" => "10" }))

        expect(sleeps.first).to eq(10.0)
        expect(sleeps.drop(1).first(2)).to eq([10.0, 10.0])
      end

      it "keeps the computed delay when it exceeds Retry-After" do
        run_with(http_error(headers: { "retry-after" => "1" }))

        expect(sleeps).to eq([2.0, 4.0, 8.0, 16.0])
      end

      it "caps the Retry-After sleep at 30 seconds" do
        run_with(http_error(headers: { "retry-after" => "100" }))

        expect(sleeps.first).to eq(30.0)
      end

      it "honors retry-after-ms" do
        run_with(http_error(headers: { "retry-after-ms" => "5000" }))

        expect(sleeps.first).to eq(5.0)
      end

      it "honors an HTTP-date Retry-After" do
        run_with(http_error(headers: { "retry-after" => (Time.now + 25).httpdate }))

        expect(sleeps.first).to be_between(22.0, 25.0)
      end

      it "reads symbol-keyed headers" do
        run_with(http_error(headers: { "Retry-After": "10" }))

        expect(sleeps.first).to eq(10.0)
      end

      ["soon", "-5", "", "-1000"].each do |value|
        it "ignores an unparseable or negative Retry-After (#{value.inspect})" do
          run_with(http_error(headers: { "retry-after" => value, "retry-after-ms" => value }))

          expect(sleeps).to eq([2.0, 4.0, 8.0, 16.0])
        end
      end

      it "ignores an HTTP-date Retry-After in the past" do
        run_with(http_error(headers: { "retry-after" => (Time.now - 60).httpdate }))

        expect(sleeps.first).to eq(2.0)
      end

      it "keeps 0.5 and 1.0 with 3 attempts for a 500, ignoring Retry-After" do
        run_with(http_error(500, headers: { "retry-after" => "20" }))

        expect(sleeps).to eq([0.5, 1.0])
        expect(batch_clause_annotator).to have_received(:call).exactly(3).times
      end

      it "keeps 0.5 and 1.0 with 3 attempts for a timeout" do
        run_with(Timeout::Error.new("slow"))

        expect(sleeps).to eq([0.5, 1.0])
        expect(batch_clause_annotator).to have_received(:call).exactly(3).times
      end

      it "never retries a 400, even with a Retry-After header" do
        run_with(http_error(400, headers: { "retry-after" => "1" }))

        expect(sleeps).to be_empty
        expect(batch_clause_annotator).to have_received(:call).once
      end

      # rubocop:disable-next RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers -- shares the 429 fakes
      describe "retry evidence" do
        let(:body) do
          { error: { message: "Provider returned error", code: 429, metadata: { provider_name: "DeepInfra" } } }
        end
        let(:headers) do
          {
            "Authorization" => "Bearer sk-secret",
            "Retry-After" => "10",
            "X-RateLimit-Remaining" => "0",
            "Content-Type" => "application/json",
            "set-cookie" => "k=v",
          }
        end
        let(:evidence) do
          {
            status: 429,
            retry_after: "10",
            provider: "DeepInfra",
            ratelimit_headers: { "retry-after" => "10", "x-ratelimit-remaining" => "0" },
          }
        end

        it "logs status, retry_after, allow-listed ratelimit headers and provider on each retry" do
          run_with(http_error(headers:, body:))

          expect(logger).to have_received(:warn)
            .with(a_string_including("attempt failed, retrying"), hash_including(evidence)).exactly(4).times
        end

        it "logs the same evidence when retries are exhausted" do
          run_with(http_error(headers:, body:))

          expect(logger).to have_received(:warn)
            .with(a_string_including("retries exhausted"), hash_including(evidence.merge(attempt: 5, max_attempts: 5)))
        end

        it "does not log retries-exhausted for a non-retryable error" do
          run_with(http_error(400, headers:, body:))

          expect(logger).not_to have_received(:warn).with(a_string_including("retries exhausted"), any_args)
        end

        it "never logs credentials or non-allow-listed headers" do
          logged = []
          allow(logger).to receive(:warn) { |*args, **fields| logged << [args, fields].inspect }
          run_with(http_error(headers:, body:))

          expect(logged.join).not_to include("sk-secret", "Authorization", "set-cookie", "Content-Type")
        end

        it "logs symbol-keyed headers lowercased" do
          run_with(http_error(headers: { "X-RateLimit-Limit": 100, "Retry-After": "10" }, body:))

          expect(logger).to have_received(:warn).with(
            a_string_including("retrying"),
            hash_including(ratelimit_headers: { "x-ratelimit-limit" => "100", "retry-after" => "10" })
          ).at_least(:once)
        end

        it "finds headers and body on an error in the cause chain" do
          inner = http_error(headers:, body:)
          outer = begin
            raise StandardError, "OpenAI adapter error: {status: 429, message: rate limited}", cause: inner
          rescue => e
            e
          end
          run_with(outer)

          expect(logger).to have_received(:warn).with(a_string_including("retrying"), hash_including(evidence))
            .at_least(:once)
          expect(sleeps.first).to eq(10.0)
        end

        it "logs status nil, retry_after nil, {} and nil provider when nothing is available" do
          run_with(Timeout::Error.new("slow"))

          expect(logger).to have_received(:warn).with(
            a_string_including("retrying"),
            hash_including(status: nil, retry_after: nil, ratelimit_headers: {}, provider: nil)
          ).at_least(:once)
        end

        [nil, "plain", 42, [], ["a"]].each do |odd|
          it "does not raise when headers are #{odd.inspect}" do
            expect { run_with(http_error(headers: odd, body: odd)) }.not_to raise_error
            expect(sleeps).to eq([2.0, 4.0, 8.0, 16.0])
          end
        end
      end
    end

    describe "provider error body" do
      let(:logger) { instance_spy(SFL::Core::Ports::JournaldLogger) }
      let(:errors) { [] }
      let(:status_error_class) do
        Class.new(StandardError) do
          attr_reader :body

          def initialize(message, body)
            super(message)
            @body = body
          end
        end
      end

      def engine_with(batch_clause_annotator)
        allow(logger).to receive(:error) { |message, **fields| errors << [message, fields] }
        described_class.new(clause_annotator: double, batch_clause_annotator:, logger:, sleeper: -> (_) {})
      end

      def adapter_error_with(body)
        inner = status_error_class.new("400 Bad Request", body)
        begin
          raise StandardError, "OpenAI adapter error: status=400 url=https://example.test/v1/chat/completions", cause: inner
        rescue => e
          e
        end
      end

      def logged_error_message(error)
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(batch_clause_annotator).to receive(:call).and_raise(error)
        engine_with(batch_clause_annotator).annotate_batch([[clause, ideational]])
        message = nil
        expect(logger).to have_received(:error).with(a_string_including("defaulted"), hash_including(:error_message)) do |_msg, **fields|
          message = fields[:error_message]
        end
        message
      end

      it "appends the inner message of metadata.raw from the cause's body, and keeps the call at one attempt" do
        raw = { error: { message: "Input too long: 39319 input tokens, limit is 32768", code: 400 } }.to_json
        body = { error: { message: "Provider returned error", code: 400, metadata: { raw:, provider_name: "DeepInfra" } } }

        message = logged_error_message(adapter_error_with(body))

        expect(message).to include("status=400", "Input too long: 39319 input tokens, limit is 32768")
      end

      it "falls back to error.message when metadata.raw is not parseable JSON" do
        body = { error: { message: "Provider returned error", metadata: { raw: "not json {" } } }

        expect(logged_error_message(adapter_error_with(body))).to include("Provider returned error")
      end

      it "falls back to error.message when metadata is absent" do
        body = { error: { message: "bad request body" } }

        expect(logged_error_message(adapter_error_with(body))).to include("bad request body")
      end

      it "truncates the body message to about 300 characters" do
        body = { error: { message: "x" * 1000 } }

        message = logged_error_message(adapter_error_with(body))

        expect(message).to include("x" * 300)
        expect(message).not_to include("x" * 301)
      end

      [nil, "plain string", 42, { error: "just a string" }, { unrelated: true }].each do |body|
        it "does not raise and logs the adapter message when the body is #{body.inspect}" do
          message = logged_error_message(adapter_error_with(body))

          expect(message).to include("OpenAI adapter error: status=400")
        end
      end

      it "does not raise when the cause chain has no error responding to #body" do
        error = begin
          raise StandardError, "outer", cause: IOError.new("inner")
        rescue => e
          e
        end
        expect { logged_error_message(error) }.not_to raise_error
      end

      it "keeps a 400 non-retryable" do
        batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(batch_clause_annotator).to receive(:call).and_raise(adapter_error_with({ error: { message: "x" } }))

        engine_with(batch_clause_annotator).annotate_batch([[clause, ideational]])

        expect(batch_clause_annotator).to have_received(:call).once
      end
    end

    describe "bounded slices" do
      let(:logger) { instance_spy(SFL::Core::Ports::JournaldLogger) }
      let(:calls) { [] }

      def pairs_of(count)
        Array.new(count) { |i| [clause.new(id: "c-#{i}", text: "t#{i}"), ideational] }
      end

      def echo_annotator
        annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(annotator).to receive(:call) do |contexts|
          calls << contexts
          contexts.map { |c| valid_raw.merge(index: c[:index], topical_theme: c[:text]) }
        end
        annotator
      end

      def started_ids
        ids = []
        allow(logger).to receive(:info) { |message, **fields| ids << fields[:batch_id] if message == "pass_two batch started" }
        yield
        ids
      end

      def engine_sized(annotator, batch_size: 40)
        described_class.new(clause_annotator: double, batch_clause_annotator: annotator, logger:, batch_size:)
      end

      it "defaults to 40 pairs per request" do
        engine = described_class.new(clause_annotator: double, batch_clause_annotator: echo_annotator, logger:)

        engine.annotate_batch(pairs_of(41))

        expect(calls.map(&:size)).to eq([40, 1])
      end

      { 4 => [4], 5 => [5], 6 => [5, 1], 11 => [5, 5, 1], 10 => [5, 5] }.each do |count, sizes|
        it "splits #{count} pairs with batch_size 5 into slices #{sizes}" do
          results = engine_sized(echo_annotator, batch_size: 5).annotate_batch(pairs_of(count))

          expect(calls.map(&:size)).to eq(sizes)
          expect(results.size).to eq(count)
          expect(results.map { |r| r.textual.topical_theme }).to eq(Array.new(count) { |i| "t#{i}" })
          expect(results.map { |r| r.interpersonal.annotation_source }.uniq).to eq(["llm"])
        end
      end

      it "passes per-slice indices to the annotator" do
        engine_sized(echo_annotator, batch_size: 3).annotate_batch(pairs_of(7))

        expect(calls.map { |slice| slice.map { |c| c[:index] } }).to eq([[0, 1, 2], [0, 1, 2], [0]])
      end

      it "logs one started/finished pair per slice, each with its own batch_id" do
        ids = started_ids { engine_sized(echo_annotator, batch_size: 3).annotate_batch(pairs_of(7)) }

        expect(logger).to have_received(:info).with("pass_two batch started", batch_id: a_kind_of(String), size: 3).twice
        expect(logger).to have_received(:info).with("pass_two batch started", batch_id: a_kind_of(String), size: 1).once
        expect(logger).to have_received(:info)
          .with("pass_two batch finished", batch_id: a_kind_of(String), size: 3, latency_ms: a_kind_of(Numeric)).twice
        expect(ids.uniq.size).to eq(3)
      end

      it "defaults only the clauses of a failing slice and keeps the other slices' results" do
        annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
        allow(annotator).to receive(:call) do |contexts|
          raise StandardError, "OpenAI adapter error: status=400 boom" if contexts.first[:text] == "t3"

          contexts.map { |c| valid_raw.merge(index: c[:index], topical_theme: c[:text]) }
        end

        results = engine_sized(annotator, batch_size: 3).annotate_batch(pairs_of(8))

        sources = results.map { |r| r.interpersonal.annotation_source }
        expect(sources).to eq(%w[llm llm llm fallback fallback fallback llm llm])
        expect(results[3].interpersonal.reasoning).to include("StandardError", "boom")
        expect(results[6].textual.topical_theme).to eq("t6")
        expect(logger).to have_received(:error).with(
          a_string_including("3/3 clauses (100.0%) defaulted"), hash_including(missing: 3, total: 3)
        ).once
      end

      it "raises ArgumentError for a non-positive batch_size" do
        expect { engine_sized(echo_annotator, batch_size: 0) }.to raise_error(ArgumentError, /batch_size/)
      end
    end
  end

  describe "logging" do
    let(:logger) { instance_spy(SFL::Core::Ports::JournaldLogger) }

    it "logs debug on start and info with mood/tenor/latency on completion" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, logger:)

      engine.annotate(clause, ideational)

      expect(logger).to have_received(:debug).with("pass_two started", hash_including(clause_id: clause.id))
      expect(logger).to have_received(:info).with(
        "pass_two completed", hash_including(clause_id: clause.id, mood: "declarative", latency_ms: a_kind_of(Numeric))
      )
    end

    it "includes provider and model on the completion line" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, logger:,
        provider: :ollama, model: "qwen3")

      engine.annotate(clause, ideational)

      expect(logger).to have_received(:info).with(
        "pass_two completed", hash_including(provider: :ollama, model: "qwen3")
      )
    end

    it "logs a warning when a value is rejected by its contract" do
      clause_annotator = instance_double(
        SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(modality_weight: 5.0)
      )
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, logger:)

      engine.annotate(clause, ideational)

      expect(logger).to have_received(:warn)
        .with(a_string_including("invalid interpersonal"), hash_including(clause_id: clause.id))
    end

    it "logs a warning when the mood value is an unrecognized schema gap" do
      clause_annotator = instance_double(
        SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(mood: "totally_unrelated_garbage")
      )
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, logger:)

      engine.annotate(clause, ideational)

      expect(logger).to have_received(:warn)
        .with(a_string_including("unknown mood"), hash_including(dimension: :mood, raw_value: "totally_unrelated_garbage"))
    end
  end
end
