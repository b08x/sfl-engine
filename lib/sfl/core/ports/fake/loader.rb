# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # Scriptable Loader for specs. Takes an array of units and
        # yields them in order — no fixture files needed.
        class Loader
          include Ports::Loader

          # @param units [Array<SFL::Core::Types::Unit>]
          def initialize(units)
            @units = units
          end

          attr_reader :units

          def each_unit(&)
            return enum_for(:each_unit) unless block_given?

            @units.each(&)
          end
        end
      end
    end
  end
end
