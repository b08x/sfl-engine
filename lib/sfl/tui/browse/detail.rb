# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # The text of Browse's right-hand detail pane, as lines.
      module Detail
        extend self

        # @param state [State]
        # @return [Array<String>]
        def lines(state)
          clause = state.focused_clause
          return clause_lines(state, clause) if clause

          node = state.focused_row
          return ["Nothing to show. Ingest a collection with sfl-analyze ingest."] unless node
          return section_lines(state, node) if node.kind == :section

          [node.label, "#{node.kind}: #{node.data.except(:id).compact.map { |key, value| "#{key}=#{value}" }.join(' ')}"]
        end

        private def clause_lines(state, node)
          clause = node.data
          interpersonal = clause.fetch(:interpersonal, {})
          ideational = clause.fetch(:ideational, {})
          [
            "Clause #{clause[:id]}",
            "",
            clause[:text].to_s,
            "",
            "process: #{ideational[:process_type]}  mood: #{interpersonal[:mood]}  tenor: #{interpersonal[:tenor]}",
            "annotation source: #{interpersonal[:annotation_source]}",
            *annotation_lines(state.reviews.annotation(clause[:id])),
          ]
        end

        # Annotation review is shown read-only: there is no accept or reject key.
        private def annotation_lines(review)
          return [] unless review

          confidence = review[:confidence] ? format("%.2f", review[:confidence]) : "n/a"
          ["", "[annotation review: #{review[:status]}] confidence #{confidence} (read-only)"]
        end

        private def section_lines(state, node)
          section = node.data
          header = [
            node.label,
            "section #{section[:section_id]}  kind #{section[:kind]}  clauses #{section[:clause_count]}",
          ]
          item = state.reviews.item(section[:section_id])
          item ? header + review_lines(item) : header
        end

        private def review_lines(item)
          [
            "",
            "Content review: #{item[:status]} (#{item[:modality]})",
            "Reason: #{item[:reason]}",
            "Source file: #{item[:source_file]}",
            "",
            "Generated text:",
            *item[:generated_text].to_s.lines.map(&:chomp),
          ]
        end
      end
    end
  end
end
