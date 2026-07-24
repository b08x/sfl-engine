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
        def initialize(parser:, instrumenter: Ports::Null::Instrumenter.new)
          @parser = parser
          @instrumenter = instrumenter
        end

        # @param text [String] raw input text (e.g. a loader section)
        # @param document_id [String, nil]
        # @return [Array<SFL::Core::Types::SyntacticClause>]
        def process(text, document_id: nil)
          return [] if text.nil? || text.strip.empty?

          instrumenter.instrument("pass_one.process", document_id:) do
            parser.parse(text, document_id:)
          end
        rescue Error
          raise
        rescue => e
          raise Error, "Syntactic extraction failed: #{e.message}"
        end

        private

        attr_reader :parser, :instrumenter
      end
    end
  end
end
