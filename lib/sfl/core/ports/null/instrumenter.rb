# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Instrumenter: runs the block, emits no spans.
        class Instrumenter
          include Ports::Instrumenter

          def instrument(_name, _payload = {}, &)
            yield
          end
        end
      end
    end
  end
end
