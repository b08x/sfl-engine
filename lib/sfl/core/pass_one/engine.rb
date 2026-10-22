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
        # @param section_id [String, nil]
        # @return [Array<SFL::Core::Types::SyntacticClause>]
        def process(text, section_id: nil)
          return [] if text.nil? || text.strip.empty?

          parse_with_logging(text, section_id)
        rescue Error => e
          log_failure(section_id, e)
          raise
        rescue => e
          log_failure(section_id, e)
          raise Error, "Syntactic extraction failed: #{e.message}"
        end

        attr_reader :parser, :instrumenter, :logger
        private :parser, :instrumenter, :logger

        private def parse_with_logging(text, section_id)
          logger.debug("pass_one started", section_id:, text_length: text.length)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          clauses = instrumenter.instrument("pass_one.process", section_id:) do
            parser.parse(text, section_id:)
          end

          log_completion(section_id, clauses, started_at)
          clauses
        end

        private def log_completion(section_id, clauses, started_at)
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
          logger.info("pass_one completed", section_id:, clause_count: clauses.size, latency_ms: elapsed_ms)
        end

        private def log_failure(section_id, error)
          logger.error("pass_one failed", section_id:, error_class: error.class, error_message: error.message)
        end
      end
    end
  end
end
