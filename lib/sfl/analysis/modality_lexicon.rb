# frozen_string_literal: true

module SFL
  module Analysis
    # Deterministic epistemic lexicon. Maps hedge and certainty markers to a
    # modality band (:low, :median, :high), or nil when none is present.
    #
    # Two uses share it: the narrative grounding check weights each claim by
    # its band, and the Pass 2 gold labels use it as the reference for
    # modality on lexically marked clauses. Rules:
    #
    # - Matching is case-insensitive, on whole words. Multi-word markers
    #   ("i think", "of course") match only as contiguous phrases.
    # - Text inside straight or curly double quotes is ignored. Quoted speech
    #   belongs to the quoted speaker, not to the clause that quotes it.
    # - A marker preceded within two tokens by a negator (not, no, cannot, or
    #   any n't contraction) flips low and high. "can't possibly" is high.
    #   Median does not flip.
    # - When a text has several markers, the first one decides.
    class ModalityLexicon
      # Markers as written. Multi-word markers are matched as contiguous phrases.
      BANDS = {
        low: %w[might may could perhaps maybe possibly] + ["i think", "it seems", "i guess", "i suppose"],
        median: %w[probably likely should would] + ["i believe"],
        high: %w[must certainly definitely clearly always never] + ["of course", "no doubt"],
      }.freeze

      # The same markers as token arrays, so a phrase is compared token by token.
      MARKERS = BANDS.transform_values { |markers| markers.map(&:split).freeze }.freeze

      NEGATORS = %w[not no cannot].freeze
      NEGATION_WINDOW = 2
      QUOTED = /"[^"]*"|“[^”]*”/

      FLIPPED = { low: :high, high: :low, median: :median }.freeze
      WORD = /[a-z]+(?:['’][a-z]+)*/

      # @param text [String, nil]
      # @return [Symbol, nil] :low, :median, :high, or nil when no marker is present
      def band(text)
        tokens = tokenize(text)
        tokens.each_index do |index|
          found = band_at(tokens, index)
          return found if found
        end
        nil
      end

      # A claim whose modality weight contradicts the text's marker. A
      # high-weight claim that hedges, or a low-weight claim that asserts, is a
      # contradiction.
      # @param modality_weight [Float] 0.0 to 1.0, as coded on the clause
      # @param text [String]
      # @return [Boolean]
      def contradiction?(modality_weight, text)
        case band(text)
        when :low then modality_weight >= 0.8
        when :high then modality_weight <= 0.3
        else false
        end
      end

      private def tokenize(text)
        return [] if text.nil?

        text.gsub(QUOTED, " ").downcase.scan(WORD).map { |word| word.tr("’", "'") }
      end

      # The band for a marker starting at +index+, or nil. No marker is a prefix
      # of another, so the order of the bands does not change the result.
      private def band_at(tokens, index)
        MARKERS.each do |band, phrases|
          next unless phrases.any? { |phrase| phrase_at?(tokens, index, phrase) }

          return negated?(tokens, index) ? FLIPPED.fetch(band) : band
        end
        nil
      end

      private def phrase_at?(tokens, index, phrase)
        tokens[index, phrase.size] == phrase
      end

      private def negated?(tokens, index)
        from = [index - NEGATION_WINDOW, 0].max
        tokens[from...index].any? { |word| NEGATORS.include?(word) || word.end_with?("n't") }
      end
    end
  end
end
