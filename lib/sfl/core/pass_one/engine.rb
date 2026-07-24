# frozen_string_literal: true

module SFL
  module Core
    module PassOne
      # Pass 1 use case: turns raw text into syntactic clauses. Delegates
      # the actual parsing to an injected SyntacticParser port (in
      # production, SpacySidecarParser; in tests, Null/Fake) — this class
      # owns only the guard clause, instrumentation span, and error
      # translation, so swapping the parser never touches this file.
      class Engine
        def initialize(parser:, instrumenter: Ports::Null::Instrumenter.new, logger: Ports::Null::Logger.new)
          @parser = parser
          @instrumenter = instrumenter
          @logger = logger
        end

        # @param text [String] raw input text (e.g. a loader section)
        # @param document_id [String, nil]
        # @return [Array<SFL::Core::Types::SyntacticClause>]
        def process(text, document_id: nil)
          return [] if text.nil? || text.strip.empty?

          parse_with_logging(text, document_id)
        rescue Error => e
          log_failure(document_id, e)
          raise
        rescue => e
          log_failure(document_id, e)
          raise Error, "Syntactic extraction failed: #{e.message}"
        end

        attr_reader :parser, :instrumenter, :logger
        private :parser, :instrumenter, :logger

        private def parse_with_logging(text, document_id)
          logger.debug { "pass_one started (document_id=#{document_id.inspect}, text_length=#{text.length})" }
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          clauses = instrumenter.instrument("pass_one.process", document_id:) do
            parser.parse(text, document_id:)
          end

          log_completion(document_id, clauses, started_at)
          clauses
        end

        private def log_completion(document_id, clauses, started_at)
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
          logger.info do
            "pass_one completed (document_id=#{document_id.inspect}, clause_count=#{clauses.size}, " \
              "latency_ms=#{elapsed_ms})"
          end
        end

        private def log_failure(document_id, error)
          logger.error { "pass_one failed (document_id=#{document_id.inspect}): #{error.message}" }
        end
      end
    end
  end
end
