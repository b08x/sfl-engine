# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # Deterministic Embedder for specs that need controllable vector
        # output without a real embedding API call — pairs with
        # PgHybridRetriever specs that assert on semantic-arm ranking, where
        # Null::Embedder's always-empty vector would just skip that arm
        # entirely. Vectors are supplied per exact input text; any text not
        # registered gets a caller-supplied default (a zero vector, matching
        # the `vector(768)` column in db/migrations/004) rather than
        # raising, so a spec that only cares about a subset of inputs
        # doesn't need to enumerate every one.
        class Embedder
          include Ports::Embedder

          DIMENSIONS = 768

          def initialize(vectors: {}, default: Array.new(DIMENSIONS, 0.0))
            @vectors = vectors
            @default = default
          end

          def embed(text)
            @vectors.fetch(text, @default)
          end

          def embed_batch(texts)
            texts.map { |text| embed(text) }
          end
        end
      end
    end
  end
end
