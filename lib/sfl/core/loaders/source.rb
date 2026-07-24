# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Duck every loader implements: turn a file into a stream of
      # Types::Unit. `#units` is the one method built on top of the
      # required `#each_unit` — concrete sources never need to implement
      # both.
      module Source
        # @yield [SFL::Core::Types::Unit]
        # @return [Enumerator] if no block given
        def each_unit
          raise NotImplementedError, "#{self.class} must implement #each_unit"
        end

        # @return [Array<SFL::Core::Types::Unit>]
        def units
          each_unit.to_a
        end
      end
    end
  end
end
