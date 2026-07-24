# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Produces vector embeddings for clause/document text, for pgvector
      # storage and hybrid retrieval.
      module Embedder
        # @param text [String]
        # @return [Array<Float>]
        def embed(text)
          raise NotImplementedError, "#{self.class} must implement #embed"
        end

        # @param texts [Array<String>]
        # @return [Array<Array<Float>>] one vector per input text, same order
        def embed_batch(texts)
          raise NotImplementedError, "#{self.class} must implement #embed_batch"
        end
      end
    end
  end
end
