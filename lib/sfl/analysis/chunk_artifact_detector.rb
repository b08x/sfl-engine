# frozen_string_literal: true

module SFL
  module Analysis
    # Flags clauses likely fragmented by a PDF chunk boundary rather than
    # a real sentence end. Pass 2 sees an ambiguous fragment ("The system
    # was") and silently defaults to 0.5 modality/tenor — a false
    # measurement disguised as data. Operates on plain clause-like
    # objects (anything responding to #text) and integer chunk boundary
    # indices, so it has no dependency on Engine, DocumentationSource, or
    # any particular loader — Engine's #build_result composes it with
    # whatever boundary indices a Source hands back from its own
    # `#chunk_boundaries` hook (see DocumentationSource).
    #
    # Scope: implements the card's primary heuristic (terminal
    # punctuation + continuation-start). The "alternatively" spaCy
    # sentence-span heuristic mentioned alongside it is not implemented —
    # it would require re-running sentence segmentation across a chunk
    # boundary the syntactic engine never saw as contiguous text, which
    # is a materially bigger change than this card's four requirements ask for.
    class ChunkArtifactDetector
      TERMINAL_PUNCTUATION = [".", "!", "?", "\""].freeze
      CONTINUATION_WORDS = %w[and but or because although though since unless while which that where when].freeze

      # @param clauses [Array<#text>] flat, document-order clauses
      # @param chunk_boundaries [Array<Integer>] clause indices where a
      #   new PDF chunk begins (the boundary sits between index-1 and index)
      # @return [Array<Integer>] indices of clauses likely split across
      #   a chunk boundary — both the truncated tail and the continued head
      def self.detect(clauses, chunk_boundaries)
        new(clauses, chunk_boundaries).detect
      end

      def initialize(clauses, chunk_boundaries)
        @clauses = clauses
        @chunk_boundaries = chunk_boundaries
      end

      def detect
        @chunk_boundaries.each_with_object([]) do |boundary, affected|
          prev_index = boundary - 1
          next unless prev_index >= 0 && boundary < @clauses.size
          next unless mid_sentence_split?(@clauses[prev_index].text, @clauses[boundary].text)

          affected << prev_index << boundary
        end.uniq.sort
      end

      private def mid_sentence_split?(prev_text, next_text)
        !terminal_punctuation?(prev_text) && continuation_start?(next_text)
      end

      private def terminal_punctuation?(text)
        TERMINAL_PUNCTUATION.include?(text.to_s.rstrip[-1])
      end

      private def continuation_start?(text)
        first_word = text.to_s.lstrip[/\A[A-Za-z']+/]
        return false unless first_word

        lowercase_start?(first_word) || CONTINUATION_WORDS.include?(first_word.downcase)
      end

      private def lowercase_start?(word)
        word[0] == word[0].downcase && word[0] != word[0].upcase
      end
    end
  end
end
