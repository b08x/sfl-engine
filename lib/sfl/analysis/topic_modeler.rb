# frozen_string_literal: true

module SFL
  module Analysis
    # Assigns topics to conversation turns with the BERTopic sidecar
    # (BertopicSidecar) over embeddings from an injected Core::Ports::Embedder.
    #
    # Each turn gets a one-hot topic distribution over its topic. Outlier
    # turns (topic -1) get an empty distribution, so their coherence is nil.
    #
    # Topic-path input passes through TopicInputCleaner before embedding and
    # before the sidecar call. Coverage is the non-outlier share of turns. A
    # first fit at or below COVERAGE_GATE is retried once with a smaller
    # nr_topics and min_topic_size; a second miss raises TopicCoverageError.
    #
    # Reads no ENV. Every dependency is a constructor argument.
    # rubocop:disable Metrics/ClassLength -- one adapter around the sidecar: fit with the
    # coverage gate, one-hot assignment, coherence and shift detection; each its own method.
    class TopicModeler
      COVERAGE_GATE = 0.30
      MIN_TOPIC_SIZE_FLOOR = 2
      MIN_TOPIC_COUNT = 2
      PROBE_TEXT = "topic model embedder probe"

      # @param embedder [Core::Ports::Embedder] embeds every turn and the probe string
      # @param sidecar_command [Array<String>] argv that starts the BERTopic sidecar
      # @param k [Integer, nil] requested topic count (nr_topics); nil lets BERTopic choose
      # @param seed [Integer]
      # @param speaker_names [Array<String>] speaker labels stripped by TopicInputCleaner
      # @param embedder_info [Hash] :provider, :model and :endpoint, named in probe errors
      # @param sidecar [#fit, nil] a client to use instead of one built from sidecar_command
      # @param store [SFL::Store::PgTopicModelStore, nil] when set, each successful fit is saved
      # @param collection_key [String, nil] required with store
      # @param document_key [String, nil] required with store
      # @param run_id [String, nil] SFL_RUN_ID stored with the fit
      # @param logger [Core::Ports::Logger]
      # rubocop:disable Metrics/ParameterLists, Naming/MethodParameterName -- every keyword is an
      # independent injected collaborator or setting; k: is the sidecar's nr_topics under the name the
      # engine's factory call uses.
      def initialize(embedder:, sidecar_command:, k: nil, seed: 42, speaker_names: [], embedder_info: {},
        sidecar: nil, store: nil, collection_key: nil, document_key: nil, run_id: nil,
        logger: Core::Ports::Null::Logger.new
      )
        # rubocop:enable Metrics/ParameterLists, Naming/MethodParameterName
        raise Error, "a topic model store requires collection_key and document_key" if store && (collection_key.nil? || document_key.nil?)

        @embedder = embedder
        @embedder_info = embedder_info
        @k = k
        @seed = seed
        @cleaner = TopicInputCleaner.new(speaker_names:)
        @sidecar = sidecar || BertopicSidecar.new(command: sidecar_command, logger:)
        @store = store
        @collection_key = collection_key
        @document_key = document_key
        @run_id = run_id
        @logger = logger
        @probed = false
        @topic_labels = {}
        @turns = nil
        @fitted = false
      end

      # @param turns [Array<Core::Types::ConversationTurn>]
      # @return [Hash] :topics (Array<Integer>), :topic_words (Hash<Integer, Array<String>>),
      #   :coverage (Float) and :attempts (Integer)
      # @raise [TopicCoverageError] when both attempts are at or below the coverage gate
      def fit(turns)
        @turns = turns
        texts = @cleaner.call(turns.map(&:message_text))
        embeddings = embed_turns(texts)

        result = fit_with_gate(texts, embeddings)
        @store&.save(collection_key: @collection_key, document_key: @document_key, result:, run_id: @run_id)

        @topic_labels = result.fetch(:topic_words)
        @turns = assign_topics_to_turns(turns, result.fetch(:topics))
        @fitted = true
        assign_coherence_scores_to_turns
        result
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

      # Mean of the non-empty per-turn distributions.
      # @return [Hash{Integer => Float}]
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

      private def fit_with_gate(texts, embeddings)
        first_min = default_min_topic_size(texts.size)
        first = sidecar_fit(texts, embeddings, nr_topics: @k, min_topic_size: first_min)
        return first.merge(attempts: 1) if passes_gate?(first)

        first_count = topic_count(first)
        retry_k = [MIN_TOPIC_COUNT, first_count / 2].max
        retry_min = [MIN_TOPIC_SIZE_FLOOR, first_min / 2].max
        @logger.warn("topic coverage at or below gate, retrying once with smaller settings",
          coverage: first[:coverage], topics: first_count, gate: COVERAGE_GATE,
          retry_k:, retry_min_topic_size: retry_min)

        second = sidecar_fit(texts, embeddings, nr_topics: retry_k, min_topic_size: retry_min)
        return second.merge(attempts: 2) if passes_gate?(second)

        raise TopicCoverageError,
          "topic coverage gate (> #{COVERAGE_GATE}) failed after 2 attempts: " \
            "attempt 1 coverage #{first[:coverage]} with #{first_count} topics, " \
            "attempt 2 coverage #{second[:coverage]} with #{topic_count(second)} topics"
      end

      private def sidecar_fit(texts, embeddings, nr_topics:, min_topic_size:)
        @sidecar.fit(texts:, embeddings:, seed: @seed, k: nr_topics, min_topic_size:)
      end

      private def passes_gate?(result) = result[:coverage] > COVERAGE_GATE

      private def topic_count(result) = result[:topics].reject { |topic| topic == BertopicSidecar::OUTLIER_TOPIC }.uniq.size

      # Single place that mirrors the sidecar client's own default.
      private def default_min_topic_size(text_count) = [MIN_TOPIC_SIZE_FLOOR, text_count / 10].max

      private def embed_turns(texts)
        probe_embedder!
        vectors = @embedder.embed_batch(texts)
        return vectors if vectors.size == texts.size

        raise Error, "#{embedder_label} returned #{vectors.size} vectors for #{texts.size} turns"
      end

      private def probe_embedder!
        return if @probed

        vector = begin
          @embedder.embed(PROBE_TEXT)
        rescue => e
          raise Error, "#{embedder_label} probe failed: #{e.class}: #{e.message}"
        end
        raise Error, "#{embedder_label} probe returned an empty vector" if vector.nil? || vector.empty?

        @probed = true
      end

      private def embedder_label
        provider = @embedder_info.fetch(:provider, "unknown")
        model = @embedder_info.fetch(:model, "unknown")
        endpoint = @embedder_info.fetch(:endpoint, "unknown")
        "topic embedder (provider: #{provider}, model: #{model}, endpoint: #{endpoint})"
      end

      private def assign_topics_to_turns(turns, topics)
        turns.zip(topics).map do |turn, topic|
          outlier = topic == BertopicSidecar::OUTLIER_TOPIC
          turn.new(topic_distribution: outlier ? {} : { topic => 1.0 }, dominant_topic: outlier ? nil : topic)
        end
      end

      # ported verbatim from legacy.
      private def assign_coherence_scores_to_turns
        baseline_dist = conversation_baseline
        @turns = @turns.each_with_index.map do |turn, idx|
          score = coherence_score_for(turn, idx, baseline_dist)
          turn.new(semantic_coherence_score: score)
        end
      end

      private def coherence_score_for(turn, idx, baseline_dist)
        return nil if idx < 2
        return nil if baseline_dist.empty?
        return nil if turn.topic_distribution.nil? || turn.topic_distribution.empty?

        calculate_coherence(turn.topic_distribution, baseline_dist)
      end

      # ported verbatim from legacy's detect_topic_shifts loop body.
      private def topic_shift_for(prev, curr, threshold)
        prev_dominant = prev.dominant_topic
        curr_dominant = curr.dominant_topic
        return [] if prev_dominant.nil? || curr_dominant.nil?
        return [] if prev_dominant == curr_dominant

        distance = cosine_distance(prev.topic_distribution || {}, curr.topic_distribution || {})
        return [] if distance < threshold

        [
{
  turn_id: curr.turn_id,
  type: "topic_shift",
  from_topic: prev_dominant,
  to_topic: curr_dominant,
  magnitude: distance.round(4),
  description: "Topic shifted from #{topic_name(prev_dominant)} " \
    "to #{topic_name(curr_dominant)} (distance: #{distance.round(3)})",
},
]
      end

      private def cosine_distance(dist_a, dist_b)
        keys = dist_a.keys | dist_b.keys
        return 1.0 if keys.empty?

        dot = keys.sum { |k| (dist_a[k] || 0.0) * (dist_b[k] || 0.0) }
        mag_a = Math.sqrt(dist_a.values.sum { |v| v ** 2 })
        mag_b = Math.sqrt(dist_b.values.sum { |v| v ** 2 })

        return 1.0 if mag_a.zero? || mag_b.zero?

        (1.0 - (dot / (mag_a * mag_b))).round(4)
      end

      private def topic_name(topic_id)
        words = @topic_labels[topic_id] || []
        words.empty? ? "topic #{topic_id}" : words.first(3).join("/")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
