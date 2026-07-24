# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # Always-closed Breaker: calls the block directly, no timeout, no
        # failure counting. Useful in tests that don't care about
        # resilience behavior.
        class Breaker
          include Ports::Breaker

          def call(_label, &)
            yield
          end
        end
      end
    end
  end
end
