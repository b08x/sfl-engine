# frozen_string_literal: true

require "amatch"

module SFL
  module Analysis
    # Checks a generated narrative against the digest it was written from.
    #
    # The digest is the authority and the narrative is untrusted narration.
    # Five checks run on every sentence:
    #
    # - numbers: each figure or percentage must match a digest value within
    #   rounding (±0.5 on percentages, ±0.005 on decimals, exact for integers);
    # - turn references: `turn N` / `turns N–M` must exist, and any speaker,
    #   mood or shift attribute in the same sentence must match that turn's row;
    # - quotes: a quote of four or more words must appear in a turn preview
    #   (normalized containment, or Jaro-Winkler ≥ 0.85);
    # - causal connectives: `because` / `therefore` / `so` / `as a result` with
    #   turn references needs a KEY MOMENT or a tenor_shift on those turns or an
    #   adjacent one. Otherwise it counts as fabricated causation;
    # - temporal connectives: `first` / `then` / `after that` with turn
    #   references must cite them in turn order.
    #
    # Each checked item is a claim. A claim's weight comes from the certainty
    # band of its sentence, using the same ModalityLexicon as the Pass 2 modality
    # labels: high 1.0, median 0.6, low 0.3, unmarked 1.0. A hedged false claim
    # costs less than an asserted one. Weighted precision is
    # 1 − failed_weight / total_weight.
    # rubocop:disable-next Metrics/ClassLength -- one pass of five checks sharing one Context; each check is already its own small method.
    class DigestGroundingChecker
      Claim = Struct.new(:check, :failed, :detail, keyword_init: true)
      Finding = Struct.new(:check, :section, :sentence, :detail, :band, :weight, keyword_init: true)
      Result = Struct.new(:findings, :claim_count, :weighted_total, :weighted_failed, keyword_init: true) do
        def weighted_precision
          return 1.0 if weighted_total.zero?

          1.0 - (weighted_failed / weighted_total)
        end

        def fabricated_causation
          findings.count { |finding| finding.check == :causal_connective }
        end
      end

      BAND_WEIGHTS = { high: 1.0, median: 0.6, low: 0.3 }.freeze
      UNMARKED_WEIGHT = 1.0

      MIN_QUOTE_WORDS = 4
      QUOTE_SIMILARITY = 0.85
      PERCENT_TOLERANCE = 0.5
      FRACTION_TOLERANCE = 0.005
      ADJACENT_TURNS = 1

      # A number not preceded by a word character, a dot or a hyphen (so `2-3`
      # and `word2` do not match), with an optional decimal part and percent sign.
      NUMBER_RE = /(?<![\w.-])\d+(?:\.\d+)?%?(?!\w)/
      TURN_RE = /\bturns?\s+(\d+)(?:\s*(?:–|-|to|through|and)\s*(\d+))?/i
      QUOTE_RE = /"([^"]+)"|“([^”]+)”/
      CAUSAL_RE = /\b(?:because|therefore|so|as a result)\b/i
      TEMPORAL_RE = /\b(?:first|then|after that|afterwards)\b/i
      SHIFT_RE = /\bshifts?\b/i
      NEGATION_RE = /\b(?:no|not|without|never)\b|n't\b/i
      MOODS = %w[declarative interrogative imperative exclamative].freeze
      SENTENCE_SPLIT = /(?<=[.!?])\s+/

      # @param sections [Hash{Symbol => String}] narrative section key => text
      # @param digest [Analysis::NarrativeGenerator::Digest]
      # @return [Result]
      def check(sections, digest)
        context = Context.new(digest)
        claims = []
        findings = []

        sections.each do |section, text|
          split_sentences(text).each do |sentence|
            band = lexicon.band(sentence)
            weight = BAND_WEIGHTS.fetch(band, UNMARKED_WEIGHT)
            sentence_claims(sentence, context).each do |claim|
              claims << [claim, weight]
              next unless claim.failed

              findings << Finding.new(check: claim.check, section:, sentence:, detail: claim.detail, band:, weight:)
            end
          end
        end

        Result.new(
          findings:,
          claim_count: claims.size,
          weighted_total: claims.sum { |_claim, weight| weight },
          weighted_failed: claims.sum { |claim, weight| claim.failed ? weight : 0.0 }
        )
      end

      private def lexicon
        @lexicon ||= ModalityLexicon.new
      end

      private def split_sentences(text)
        text.to_s.split(SENTENCE_SPLIT).map(&:strip).reject(&:empty?)
      end

      private def sentence_claims(sentence, context)
        refs = turn_references(sentence)
        number_claims(sentence, context) +
          turn_claims(sentence, context, refs) +
          quote_claims(sentence, context) +
          connective_claims(sentence, context, refs)
      end

      # -- numbers -------------------------------------------------------------

      private def number_claims(sentence, context)
        scrub(sentence).scan(NUMBER_RE).map do |literal|
          grounded = grounded_number?(literal, context.numbers)
          Claim.new(check: :number, failed: !grounded,
            detail: grounded ? "#{literal} matches a digest value" : "#{literal} has no digest value")
        end
      end

      # Quoted spans belong to the quoted speaker, and turn references are not
      # figures. Both are removed before numbers are read.
      private def scrub(sentence)
        sentence.gsub(QUOTE_RE, " ").gsub(TURN_RE, " ")
      end

      # @param literal [String] a number as it appears in the narrative
      # @param digest_numbers [Array<Array(Float, Boolean)>] digest value and whether it was a percentage
      private def grounded_number?(literal, digest_numbers)
        value = literal.delete("%").to_f
        if literal.end_with?("%")
          digest_numbers.any? do |number, digest_percent|
            as_percent = digest_percent ? number : number * 100.0
            (as_percent - value).abs <= PERCENT_TOLERANCE
          end
        elsif literal.include?(".")
          digest_numbers.any? do |number, digest_percent|
            candidates = digest_percent ? [number, number / 100.0] : [number]
            candidates.any? { |candidate| (candidate - value).abs <= FRACTION_TOLERANCE }
          end
        else
          digest_numbers.any? { |number, _digest_percent| number == value }
        end
      end

      # -- turn references -----------------------------------------------------

      # @return [Array<Array(Array<Integer>, Integer, Integer)>] for each reference,
      #   the turn ids it covers, the first id and the last id, in textual order
      private def turn_references(sentence)
        sentence.scan(TURN_RE).map do |first, last|
          from = first.to_i
          to = (last || first).to_i
          [(from..to).to_a, from, to]
        end
      end

      private def turn_claims(sentence, context, refs)
        refs.flat_map do |ids, from, to|
          unknown = ids.reject { |id| context.turns.key?(id) }
          existence = Claim.new(check: :turn_reference, failed: unknown.any?,
            detail: unknown.any? ? "turn #{unknown.join(', ')} does not exist" : "turn #{from}–#{to} exists")
          next [existence] if unknown.any? || from != to

          [existence] + attribute_claims(sentence, context, from)
        end
      end

      # Attribute checks apply to a single, existing turn only. A range is too
      # coarse to say which turn the attribute belongs to.
      private def attribute_claims(sentence, context, id)
        row = context.turns.fetch(id)
        [
          speaker_claim(sentence, context, row, id),
          mood_claim(sentence, row, id),
          shift_claim(sentence, row, id),
        ].compact
      end

      private def speaker_claim(sentence, context, row, id)
        mentioned = context.speaker_names.select { |name| sentence.include?(name) }
        return nil if mentioned.empty?

        matches = mentioned.include?(row["speaker"].to_s)
        Claim.new(check: :turn_attribute, failed: !matches,
          detail: if matches
                    "speaker matches turn #{id}"
                  else
                    "turn #{id} is spoken by #{row['speaker']}, not #{mentioned.join(', ')}"
          end)
      end

      private def mood_claim(sentence, row, id)
        mentioned = MOODS.select { |mood| sentence.match?(/\b#{mood}\b/i) }
        return nil if mentioned.empty?

        matches = mentioned.include?(row["dominant_mood"].to_s)
        Claim.new(check: :turn_attribute, failed: !matches,
          detail: if matches
                    "mood matches turn #{id}"
                  else
                    "turn #{id} has mood #{row['dominant_mood']}, not #{mentioned.join(', ')}"
          end)
      end

      private def shift_claim(sentence, row, id)
        return nil unless sentence.match?(SHIFT_RE) && !sentence.match?(NEGATION_RE)

        shifted = !row["tenor_shift"].nil?
        Claim.new(check: :turn_attribute, failed: !shifted,
          detail: shifted ? "shift matches turn #{id}" : "turn #{id} records no tenor shift")
      end

      # -- quotes --------------------------------------------------------------

      private def quote_claims(sentence, context)
        sentence.scan(QUOTE_RE).map { |straight, curly| straight || curly }.filter_map do |quote|
          normalized = normalize(quote)
          next if normalized.split.size < MIN_QUOTE_WORDS

          grounded = context.previews.any? { |preview| quote_matches?(normalized, preview) }
          Claim.new(check: :quote, failed: !grounded,
            detail: grounded ? "quote found in a turn preview" : "quote not found in any turn preview: #{quote.inspect}")
        end
      end

      # A quote is found when it appears verbatim, or when some span of the
      # preview with the same word count scores at least QUOTE_SIMILARITY.
      # Comparing against the whole preview would dilute the score with words
      # the quote never contained.
      private def quote_matches?(normalized_quote, preview)
        normalized_preview = normalize(preview)
        return true if normalized_preview.include?(normalized_quote)

        matcher = Amatch::JaroWinkler.new(normalized_quote)
        words = normalized_preview.split
        width = normalized_quote.split.size
        last_start = [words.size - width, 0].max
        (0..last_start).any? do |start|
          matcher.match(words[start, width].join(" ")) >= QUOTE_SIMILARITY
        end
      end

      private def normalize(text)
        text.downcase.gsub(/[^\p{L}\p{N}\s]/, " ").squeeze(" ").strip
      end

      # -- connectives ---------------------------------------------------------

      private def connective_claims(sentence, context, refs)
        return [] if refs.empty?

        claims = []
        claims << causal_claim(sentence, context, refs.flat_map(&:first)) if sentence.match?(CAUSAL_RE)
        claims << temporal_claim(refs) if sentence.match?(TEMPORAL_RE) && refs.size >= 2
        claims
      end

      # Fabricated causation: the causal claim needs a KEY MOMENT or a
      # tenor_shift on the cited turns or an adjacent one.
      private def causal_claim(_sentence, context, ids)
        neighbourhood = ids.flat_map { |id| ((id - ADJACENT_TURNS)..(id + ADJACENT_TURNS)).to_a }
        supported = context.key_moment_turns.intersect?(neighbourhood) ||
          context.shift_turns.intersect?(neighbourhood)
        Claim.new(check: :causal_connective, failed: !supported,
          detail: if supported
                    "causal claim has a key moment or shift at its turns"
                  else
                    "causal claim with no key moment or tenor_shift at turns #{ids.uniq.join(', ')} (fabricated causation)"
          end)
      end

      private def temporal_claim(refs)
        ordered = refs.map { |_ids, from, _to| from }
        in_order = ordered.each_cons(2).all? { |earlier, later| earlier <= later }
        Claim.new(check: :temporal_connective, failed: !in_order,
          detail: if in_order
                    "turns cited in order #{ordered.join(' → ')}"
                  else
                    "turns cited against turn order #{ordered.join(' → ')}"
          end)
      end

      # Digest values the checks compare against, computed once per check run.
      class Context
        attr_reader :numbers, :turns, :previews, :key_moment_turns, :shift_turns, :speaker_names

        def initialize(digest)
          @numbers = digest.to_text.scan(NUMBER_RE).map { |literal| [literal.delete("%").to_f, literal.end_with?("%")] }
          @turns = digest.turns.to_h { |row| [row["turn_id"].to_i, row] }
          @previews = digest.turns.map { |row| row["preview"].to_s }
          @key_moment_turns = digest.key_moments.map { |km| km["turn_id"].to_i }
          @shift_turns = digest.turns.reject { |row| row["tenor_shift"].nil? }.map { |row| row["turn_id"].to_i }
          @speaker_names = digest.turns.map { |row| row["speaker"].to_s }.uniq
        end
      end
      private_constant :Context
    end
  end
end
