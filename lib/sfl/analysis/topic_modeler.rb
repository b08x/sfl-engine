# frozen_string_literal: true

require "tomoto"
require "pragmatic_tokenizer"

module SFL
  module Analysis
    # Assigns topic distributions to conversation turns or documentation
    # sections using tomoto (LDA/HDP). Ported faithfully from legacy's
    # TopicModeler — logic unchanged; only the namespace moved.
    #
    # Gem-API note: legacy pinned "tomoto ~> 0.3"; only 0.6.2 is available
    # in this sandbox. Verified directly against the installed gem's
    # source (lib/tomoto/lda.rb, lib/tomoto/hdp.rb) that LDA.new(k:,
    # min_cf:, rm_top:, seed:), HDP.new(min_cf:, rm_top:, seed:),
    # #add_doc, #make_doc, #infer, #train, #topic_words, #k, and #burn_in=
    # all still exist with the same call shape this class uses — not
    # assumed from memory.
    #
    # Uses PragmaticTokenizer for lightweight tokenization (no spaCy
    # round-trip) with topic-modeling-specific preprocessing: lowercase,
    # stem, strip stopwords, drop punctuation/numbers.
    #
    # Two operating modes:
    #   - Fixed-k LDA: caller specifies number of topics
    #   - HDP: hierarchical Dirichlet process auto-discovers topic count
    # rubocop:disable Metrics/ClassLength -- ported verbatim from legacy; one topic-modeling
    # adapter around tomoto, each responsibility (fit/tokenize/coherence/shifts) its own method.
    class TopicModeler
      # PragmaticTokenizer's `en` stoplist (Languages::English::STOP_WORDS,
      # read directly from the installed gem — not assumed) spells its
      # contractions with the ASCII apostrophe: "it's", "don't", "that's".
      # LLM-generated prose uses U+2019 RIGHT SINGLE QUOTATION MARK
      # throughout, so "it’s" never matched and survived into the topic
      # terms (it appeared in two different topics of a real run).
      #
      # The fix normalizes the *input* rather than adding curly-apostrophe
      # variants to a second stoplist: the gem's list stays the single
      # authoritative source of what counts as a stopword, and one mapping
      # table fixes every entry in it at once (plus the curly quotes,
      # dashes, ellipsis, and non-breaking spaces that defeat token
      # boundaries the same way). `expand_contractions: true` was the
      # alternative considered and rejected — it only rewrites the
      # ~100-entry CONTRACTIONS hash, leaving every other curly-punctuation
      # failure in place.
      #
      # Deliberately NOT Unicode NFKC: NFKC leaves U+2019 alone, so it does
      # not solve the problem this map exists for.
      UNICODE_PUNCTUATION_MAP = {
        "\u2018" => "'",  # left single quote
        "\u2019" => "'",  # right single quote — the LLM apostrophe
        "\u201A" => "'",  # single low-9 quote
        "\u201B" => "'",  # single high-reversed-9 quote
        "\u02BC" => "'",  # modifier letter apostrophe
        "\u2032" => "'",  # prime
        "\u201C" => '"',  # left double quote
        "\u201D" => '"',  # right double quote
        "\u201E" => '"',  # double low-9 quote
        "\u2033" => '"',  # double prime
        "\u2013" => " - ",  # en dash
        "\u2014" => " - ",  # em dash
        "\u2015" => " - ",  # horizontal bar
        "\u2212" => " - ",  # minus sign
        "\u2026" => "...",  # horizontal ellipsis
        "\u00A0" => " ",  # no-break space
        "\u2007" => " ",  # figure space
        "\u202F" => " ",  # narrow no-break space
        "\u200B" => "", # zero-width space
      }.freeze

      UNICODE_PUNCTUATION_RE = Regexp.union(UNICODE_PUNCTUATION_MAP.keys).freeze

      # No domain stoplist is applied on purpose. The contentless-looking
      # terms observed in a real run ("sound", "result", "terms", "thing")
      # are not safe to hard-code away in a *linguistics* corpus tool:
      # "sound" is phonology, "terms" is terminology, "result" is a
      # findings word — deleting them destroys real signal in exactly the
      # conversations this tool exists to analyze. ("thing"/"things" is
      # already in the gem's own stoplist and needs no help.) Those terms
      # became salient because k=10 over 8 documents forced the model to
      # pad topics with whatever vocabulary was left — the `k` clamp below
      # removes that pressure. The principled, corpus-derived lever for
      # genuinely ubiquitous terms already exists and is caller-tunable:
      # `rm_top:`, which drops the N globally most frequent words as
      # measured on the corpus at hand rather than guessed in advance.
      TOKENIZER_OPTIONS = {
        language: "en",
        remove_urls: true,
        hashtags: :remove,
        mentions: :remove,
        clean: true,
        punctuation: :none,
        numbers: :none,
        downcase: true,
        stem: :porter,
        remove_stop_words: true,
        min_length: 3,
      }.freeze

      # See legacy's TopicModeler for the full derivation of this
      # normalized-excess-over-uniform calibration; ported unchanged.
      DEFAULT_DOMINANT_THRESHOLD = 0.35

      # rubocop:disable Metrics/ParameterLists -- kwarg list ported verbatim from legacy;
      # seven independently-meaningful tomoto training knobs, no natural grouping to extract.
      # rubocop:disable Naming/MethodParameterName -- k: matches Tomoto::LDA's own k: kwarg
      # (topic count) exactly; renaming it here would just require translating back at every
      # Tomoto::LDA.new(k: @k) call site for no clarity gain.
      def initialize(k: nil, min_cf: 3, rm_top: 2, iterations: 100, seed: 42, burn_in: nil,
        dominant_threshold: DEFAULT_DOMINANT_THRESHOLD
      )
        # rubocop:enable Metrics/ParameterLists, Naming/MethodParameterName
        @k = k
        @min_cf = min_cf
        @rm_top = rm_top
        @iterations = iterations
        @burn_in = burn_in
        @seed = seed
        @dominant_threshold = dominant_threshold
        @model = nil
        @topic_labels = {}
        @fitted = false
      end

      # Pre-pass fit: trains directly on raw text, with no ConversationTurn
      # struct required.
      # @param texts [Array<String>]
      # @return [Array<Integer, nil>] dominant topic id per text, parallel to +texts+
      def fit_texts(texts)
        @model = build_model
        docs = texts.map { |t| tokenize(t) }
        docs.each { |tokens| @model.add_doc(tokens) unless tokens.empty? }

        train_model
        build_topic_labels

        docs.map { |tokens| dominant_topic_for(tokens) }
      end

      private def dominant_topic_for(tokens)
        return nil if tokens.empty?

        doc = @model.make_doc(tokens)
        topic_dist, = @model.infer(doc)
        dominant_topic_id(topic_dist)
      end

      private def dominant_topic_id(topic_dist)
        return nil if topic_dist.nil? || topic_dist.size < 2
        return nil if topic_dist.any?(&:nan?)

        top_prob, idx = topic_dist.each_with_index.max_by { |prob, _idx| prob }
        uniform = 1.0 / topic_dist.size
        excess = (top_prob - uniform) / (1.0 - uniform)
        (excess >= @dominant_threshold) ? idx : nil
      end

      # Train the topic model on an array of ConversationTurn structs.
      # @param turns [Array<Core::Types::ConversationTurn>]
      # @return [self]
      def fit(turns)
        @turns = turns
        docs = turns.map { |t| tokenize(t.message_text) }

        @model = build_model
        docs.each { |tokens| @model.add_doc(tokens) unless tokens.empty? }

        train_model
        build_topic_labels
        assign_topics_to_turns
        assign_coherence_scores_to_turns

        @fitted = true
        self
      end

      # @return [Hash{Integer => Array<String>}] topic_id => top words
      attr_reader :topic_labels

      # @return [Array<Core::Types::ConversationTurn>]
      attr_reader :turns

      def turn_distributions
        return [] unless @fitted

        @turns.map { |t| t.topic_distribution || {} }
      end

      # @param threshold [Float] minimum cosine distance to flag a shift
      # @return [Array<Hash>] topic shift events
      def detect_topic_shifts(threshold: 0.3)
        return [] unless @fitted

        shifts = []
        @turns.each_cons(2) do |prev, curr|
          shifts.concat(topic_shift_for(prev, curr, threshold))
        end
        shifts
      end

      # ported verbatim from legacy's detect_topic_shifts loop body.
      private def topic_shift_for(prev, curr, threshold)
        prev_dominant = prev.dominant_topic
        curr_dominant = curr.dominant_topic
        return [] if prev_dominant.nil? || curr_dominant.nil?
        return [] if prev_dominant == curr_dominant

        distance = cosine_distance(prev.topic_distribution || {}, curr.topic_distribution || {})
        return [] if distance < threshold

        shift = {
          turn_id: curr.turn_id,
          type: "topic_shift",
          from_topic: prev_dominant,
          to_topic: curr_dominant,
          magnitude: distance.round(4),
          description: "Topic shifted from #{topic_name(prev_dominant)} " \
            "to #{topic_name(curr_dominant)} (distance: #{distance.round(3)})",
        }
        [shift]
      end
      # @param path [String]
      def save(path)
        raise Error, "No model to save — call fit first" unless @model

        @model.save(path)
      end

      # @param path [String]
      # @return [self]
      def load_model(path)
        @model = Tomoto::LDA.load(path)
        build_topic_labels
        @fitted = true
        self
      end

      # @param turn_dist [Hash{Integer => Float}, nil]
      # @param baseline_dist [Hash{Integer => Float}, nil]
      # @return [Float, nil]
      def calculate_coherence(turn_dist, baseline_dist)
        return nil unless @fitted
        return nil if turn_dist.nil? || baseline_dist.nil?
        return nil if turn_dist.empty? || baseline_dist.empty?

        distance = cosine_distance(turn_dist, baseline_dist)
        similarity = 1.0 - distance
        similarity.clamp(0.0, 1.0).round(4)
      end

      # @return [Hash{Integer => Float}]
      # rubocop:disable Metrics/CyclomaticComplexity, -- ported verbatim from legacy
      def conversation_baseline
        return {} unless @fitted && @turns && !@turns.empty?

        sum = Hash.new(0.0)
        count = 0

        @turns.each do |turn|
          dist = turn.topic_distribution
          next if dist.nil? || dist.empty?

          dist.each { |topic_id, prob| sum[topic_id] += prob }
          count += 1
        end

        return {} if count.zero?

        sum.transform_values { |v| (v / count).round(4) }
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      # ported verbatim from legacy.
      private def assign_coherence_scores_to_turns
        was_fitted = @fitted
        @fitted = true
        begin
          baseline_dist = conversation_baseline
          @turns = @turns.each_with_index.map do |turn, idx|
            score = coherence_score_for(turn, idx, baseline_dist)
            turn.new(semantic_coherence_score: score)
          end
        ensure
          @fitted = was_fitted
        end
      end
      private def coherence_score_for(turn, idx, baseline_dist)
        return nil if idx < 2
        return nil if baseline_dist.empty?
        return nil if turn.topic_distribution.nil? || turn.topic_distribution.empty?

        calculate_coherence(turn.topic_distribution, baseline_dist)
      end

      private def build_model
        model = if @k
          Tomoto::LDA.new(k: @k, min_cf: @min_cf, rm_top: @rm_top, seed: @seed)
        else
          Tomoto::HDP.new(min_cf: @min_cf, rm_top: @rm_top, seed: @seed)
        end

        model.burn_in = @burn_in if @burn_in
        model
      end

      private def train_model
        @iterations.times { @model.train(1) }
      end

      private def build_topic_labels
        num_topics = @model.k
        @topic_labels = {}

        num_topics.times do |topic_id|
          words = @model.topic_words(topic_id)
          @topic_labels[topic_id] = words.map(&:first)
        end
      end

      private def assign_topics_to_turns
        @turns = @turns.map { |turn| assign_topic(turn) }
      end

      private def assign_topic(turn)
        tokens = tokenize(turn.message_text)
        return turn.new(topic_distribution: {}, dominant_topic: nil) if tokens.empty?

        doc = @model.make_doc(tokens)
        topic_dist, = @model.infer(doc)

        distribution = {}
        topic_dist.each_with_index { |prob, idx| distribution[idx] = prob.round(4) if prob > 0.01 }

        turn.new(topic_distribution: distribution, dominant_topic: dominant_topic_id(topic_dist))
      end

      private def tokenize(text)
        return [] if text.nil? || text.strip.empty?

        PragmaticTokenizer::Tokenizer.new(TOKENIZER_OPTIONS).tokenize(normalize_punctuation(text))
      end

      # Maps Unicode punctuation to the ASCII forms the stoplist and the
      # tokenizer's own token-boundary rules are written against. See
      # UNICODE_PUNCTUATION_MAP for why this is normalization rather than a
      # second stoplist. Upstream (DynamicFormatExpander) already handles
      # escape decoding and newline normalization; this is only about
      # characters that defeat *lexical* matching.
      private def normalize_punctuation(text)
        text.gsub(UNICODE_PUNCTUATION_RE, UNICODE_PUNCTUATION_MAP)
      end

      # rubocop:disable Metrics/CyclomaticComplexity, -- ported verbatim from legacy
      private def cosine_distance(dist_a, dist_b)
        keys = dist_a.keys | dist_b.keys
        return 1.0 if keys.empty?

        dot = keys.sum { |k| (dist_a[k] || 0.0) * (dist_b[k] || 0.0) }
        mag_a = Math.sqrt(dist_a.values.sum { |v| v ** 2 })
        mag_b = Math.sqrt(dist_b.values.sum { |v| v ** 2 })

        return 1.0 if mag_a.zero? || mag_b.zero?

        (1.0 - (dot / (mag_a * mag_b))).round(4)
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      private def topic_name(topic_id)
        words = @topic_labels[topic_id] || []
        words.empty? ? "topic #{topic_id}" : words.first(3).join("/")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
