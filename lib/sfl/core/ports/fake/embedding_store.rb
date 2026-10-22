# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory EmbeddingStore, keyed by section_id — for specs that
        # need to assert on what was actually written.
        class EmbeddingStore
          include Ports::EmbeddingStore

          def initialize
            @sections = {}
          end

          def replace_section(section_id, embeddings_by_clause_id)
            @sections[section_id] = embeddings_by_clause_id.dup
            nil
          end

          def find_by_section(section_id)
            @sections.fetch(section_id, {})
          end
        end
      end
    end
  end
end
