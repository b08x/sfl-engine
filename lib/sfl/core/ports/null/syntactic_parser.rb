# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op SyntacticParser: parses nothing, returns no clauses. Useful
        # for wiring tests that don't exercise Pass 1 at all.
        class SyntacticParser
          include Ports::SyntacticParser

          def parse(_text, document_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- document_id stays in the signature to match the SyntacticParser port contract
            []
          end
        end
      end
    end
  end
end
