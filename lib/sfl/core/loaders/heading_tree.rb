# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Nests heading-scoped units: a heading is the parent of the units that
      # follow it until a heading of the same or a higher level. A skipped
      # level (h1 then h3) nests under the nearest shallower heading. A unit
      # without a heading level (the markdown preamble) has no parent and
      # does not open a scope.
      module HeadingTree
        # @param units [Array<Types::Unit>] in document order, already filtered
        # @return [Array<Types::Unit>] the same units with parent_section_id set
        module_function def nest(units)
          stack = []
          units.map do |unit|
            level = unit.metadata["heading_level"]
            next unit unless level

            stack.pop while stack.any? && stack.last[0] >= level
            parent = stack.last&.at(1)
            stack.push([level, unit.section_id])
            unit.new(parent_section_id: parent)
          end
        end
      end
    end
  end
end
