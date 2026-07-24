# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Pass 1 port: turns raw text into syntactic clauses. The only real
      # implementation talks to the Python spaCy sidecar over NDJSON — this
      # duck-typed interface exists so Pass 2/the pipeline never reference
      # that transport directly, and so tests can swap in Null/Fake.
      module SyntacticParser
        # @param text [String]
        # @param document_id [String, nil]
        # @return [Array<SFL::Core::Types::SyntacticClause>]
        def parse(text, document_id: nil)
          raise NotImplementedError, "#{self.class} must implement #parse"
        end
      end
    end
  end
end
