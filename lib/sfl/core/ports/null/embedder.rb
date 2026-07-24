# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Embedder: returns an empty vector for any input.
        class Embedder
          include Ports::Embedder

          def embed(_text)
            []
          end

          def embed_batch(texts)
            texts.map { |text| embed(text) }
          end
        end
      end
    end
  end
end
