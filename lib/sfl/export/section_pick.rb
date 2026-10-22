# frozen_string_literal: true

module SFL
  module Export
    # One section chosen for export, with where it sits in the corpus.
    #
    # - `path`: section labels from the top-level section down to this one
    # - `depth`: nesting depth, 0 for a top-level section
    # - `order`: sort key, `[document position, section ordinal]`
    # - `clause_ids`: nil exports every clause in the section; an Array
    #   exports only those clauses
    SectionPick = Data.define(
      :collection, :document_key, :title, :source_path, :section_id, :kind, :label, :path, :depth, :order, :clause_ids
    ) do
      # @return [String, nil] the label of a turn section, nil otherwise
      def speaker = (kind == "turn") ? label : nil
    end
  end
end
