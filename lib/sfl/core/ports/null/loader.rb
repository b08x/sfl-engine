# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Loader: yields zero units. A caller that hasn't wired
        # a real loader processes nothing, silently.
        class Loader
          include Ports::Loader

          def each_unit
            enum_for(:each_unit) unless block_given?

            # yields nothing
          end
        end
      end
    end
  end
end
