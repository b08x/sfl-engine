# frozen_string_literal: true

module SFL
  module Analysis
    # The single compile loop shared by every Analysis::Source
    # (ConversationSource, DocumentationSource, and — a later slice —
    # KnowledgeBaseSource), plus the cross-turn derivations
    # (key_moments, example_passages, tenor_timeline, field_evolution,
    # topic_evolution, speaker profiling) that were three independently
    # drifting copies in legacy (D2). A Source only has to answer "what
    # are my units" (Core::Loaders::Source#each_unit, reused from Phase 1
    # rather than reinvented) and "how do I want a compiled turn reviewed"
    # (#review_entry) / "what extra metadata do I carry"
    # (#extra_metadata) — everything else lives here, once.
    #
    # Topic modeling stays a per-#analyze pre-pass fitted here (one
    # TopicModeler per call, shared by whichever Source is running) —
    # faithfully porting the CURRENT per-call duplication, not yet the
    # more ambitious "topic modeling as an engine-owned pipeline stage"
    # the card's later bullet describes.
    #
    # Storage note: Pipeline (injected) already owns clause persistence —
    # PgClauseStore#replace_document deletes+reinserts atomically (F7),
    # so unlike legacy's ConversationAnalyzer/DocumentationAnalyzer this
    # class does NOT take a clause_repo/clause_store: there is no
    # "delete before store" step left for a caller to own. The only
    # storage-shaped collaborator Engine needs directly is
    # review_queue_repo, for its own enqueue_for_review-equivalent
    # behavior (Source#review_entry decides *whether/what*; Engine is the
    # one place that actually calls the repo, again fixing a
    # once-per-analyzer duplication).
    # rubocop:disable Metrics/ClassLength -- one use case (analyze) with its compile loop plus
    # the cross-turn derivation methods it was created to stop duplicating; each already its own
    # small private method.
    class Engine
      include Aggregations

      # @param pipeline [Core::Pipeline]
      # @param review_queue_repo [Store::PgReviewQueueRepository, nil]
      # @param topic_modeler_factory [#call] `->(k:) { ... }`, defaults to
      #   TopicModeler.new(k:) — injectable so specs never pull in the real
      #   tomoto/pragmatic_tokenizer training cost
      # @param on_progress [#call, nil] see Source classes' docs for the event shape
      # @param on_turn_start [#call, nil]
      # @param stop_requested [#call, nil]
      # rubocop:disable Metrics/ParameterLists -- six independently-injectable collaborators,
      # matching Pipeline#initialize's own house style (see its class comment).
      def initialize(
        pipeline:,
        review_queue_repo: nil,
        topic_modeler_factory: -> (k:) { TopicModeler.new(k:) },
        on_progress: nil,
        on_turn_start: nil,
        stop_requested: nil
      )
        # rubocop:enable Metrics/ParameterLists
        @pipeline = pipeline
        @review_queue_repo = review_queue_repo
        @topic_modeler_factory = topic_modeler_factory
        @on_progress = on_progress
        @on_turn_start = on_turn_start
        @stop_requested = stop_requested
      end

      # @param source [#each_unit, #review_entry, #extra_metadata] a
      #   Analysis::Source implementation (ConversationSource, DocumentationSource, ...)
      # @param label [String] used for metadata[:conversation_id]/[:source_file]
      # @param store [Boolean] persist clauses + embeddings (forwarded to Pipeline#compile)
      # @param resume [Boolean] reuse cached Pass 2 results (forwarded to Pipeline#compile)
      # @param topics [Integer, nil] fixed topic count for LDA; 0 → HDP; nil = no topic modeling
      # @param pass_one_only [Boolean] forwarded to every Pipeline#compile call — see
      #   Pipeline#compile's own doc comment for why this lives there, not here
      # @return [Core::Types::AnalysisResult]
      # rubocop:disable Metrics/ParameterLists -- mirrors Pipeline#compile's own kwarg surface
      # (store/resume/pass_one_only) plus the two options only #analyze has (label/topics).
      def analyze(source, label:, store: false, resume: false, topics: nil, pass_one_only: false)
        units = source.units
        total = units.size
        compile_opts = { store:, resume:, pass_one_only: }
        _modeler, pre_turns, topic_labels, topic_shifts = fit_topics(units, topics)

        turns = compile_turns(source, units, total, compile_opts, pre_turns)
        interrupted = turns.size < total

        build_result(turns, source:, label:, total:, interrupted:, topic_labels:, topic_shifts:)
      end
      # rubocop:enable Metrics/ParameterLists

      # Builds the final AnalysisResult from already-compiled turns —
      # public the same way legacy's #build_result was, for a future
      # fan-in job that reconstructs `turns` out-of-band instead of
      # compiling them inline via #analyze's loop.
      # @param turns [Array<Core::Types::ConversationTurn>]
      # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/MethodLength -- mirrors
      # legacy's own #build_result options (label/total/interrupted/topic_labels/topic_shifts)
      # plus one AnalysisResult literal assembling every cross-turn derivation this class exists
      # to compute once instead of N times; splitting the literal further would only relocate it.
      def build_result(turns, source:, label:, total:, interrupted: false, topic_labels: nil, topic_shifts: [])
        TenorTracker.new(turns).calculate_shifts
        turns = CohesionAnalyzer.new.analyze(turns)
        profiles = SpeakerProfiler.build_profiles(turns)
        correlations = CorrelationAnalyzer.new(turns).correlate_process_tenor

        Core::Types::AnalysisResult.new(
          metadata: metadata_for(source, label, turns, total, interrupted, topic_labels),
          turns:,
          speaker_profiles: profiles,
          tenor_timeline: tenor_timeline(turns),
          field_evolution: field_evolution(turns),
          correlations:,
          insights: generate_insights(turns, topic_labels),
          key_moments: detect_key_moments(turns) + topic_shift_moments(topic_shifts),
          example_passages: detect_example_passages(turns),
          topic_labels:,
          topic_evolution: topic_evolution(turns)
        )
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/AbcSize, Metrics/MethodLength

      private def topic_shift_moments(topic_shifts)
        topic_shifts.map { |s| Core::Types::KeyMoment.new(**s.slice(:turn_id, :type, :magnitude, :description)) }
      end

      # rubocop:disable Metrics/ParameterLists -- forwards #build_result's own five options
      # plus turns/source, one flat AnalysisResult#metadata literal.
      private def metadata_for(source, label, turns, total, interrupted, topic_labels)
        {
          conversation_id: label,
          source_file: label,
          turn_count: turns.size,
          speakers: turns.map(&:speaker).uniq,
          analyzed_at: Time.now.iso8601,
          topics_enabled: !topic_labels.nil?,
          interrupted:,
          total:,
        }.merge(source.extra_metadata(turns))
      end
      # rubocop:enable Metrics/ParameterLists

      private def fit_topics(units, topics)
        return [nil, nil, nil, []] unless topics && units.size >= 3

        stub_turns = units.each_with_index.map { |unit, idx| stub_turn(unit, idx) }
        modeler = @topic_modeler_factory.call(k: topic_k(topics))
        modeler.fit(stub_turns)
        [modeler, modeler.turns, modeler.topic_labels, modeler.detect_topic_shifts]
      end

      # rubocop:disable Metrics/MethodLength -- one flat stub-turn literal, ported verbatim from
      # legacy's pre-pass stub construction; every field is an independently-meaningful neutral
      # default, not extractable further.
      private def stub_turn(unit, idx)
        Core::Types::ConversationTurn.new(
          turn_id: idx + 1,
          speaker: turn_speaker(unit),
          timestamp: unit.sent_at || Time.now,
          message_text: unit.text,
          clauses: [],
          avg_tenor: 0.5,
          avg_modality: 0.5,
          dominant_mood: "declarative",
          process_types: {},
          participants: [],
          tenor_shift: nil,
          semantic_coherence_score: nil
        )
      end
      # rubocop:enable Metrics/MethodLength

      private def turn_speaker(unit) = unit.speaker || unit.heading || unit.document_id

      # rubocop:disable Metrics/MethodLength -- one compile loop with a stop/progress/report
      # sequence per unit, ported verbatim from legacy's #analyze loop; each step is already its
      # own private method call.
      private def compile_turns(source, units, total, compile_opts, pre_turns)
        turns = []
        units.each_with_index do |unit, idx|
          break if @stop_requested&.call

          turn_id = idx + 1
          @on_turn_start&.call(turn_id:, total:, speaker: turn_speaker(unit))
          started = now

          pre_turn = pre_turns&.[](idx)
          turn = compile_turn(source, unit, turn_id, compile_opts, pre_turn)

          report_progress(turn, total, now - started)
          turns << turn
        end
        turns
      end
      # rubocop:enable Metrics/MethodLength

      private def compile_turn(source, unit, turn_id, compile_opts, pre_turn)
        semantic_coherence_score = pre_turn&.semantic_coherence_score

        compile_kwargs = { document_id: unit.document_id, embed: compile_opts[:store], **compile_opts }
        compile_kwargs[:semantic_coherence_score] = semantic_coherence_score if semantic_coherence_score

        clauses = unwrap(@pipeline.compile(unit.text, **compile_kwargs), unit.document_id)
        enqueue_review(source, unit, clauses, compile_opts[:store])

        build_turn(unit, turn_id, clauses, pre_turn, semantic_coherence_score)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- one flat ConversationTurn literal, ported verbatim from legacy
      private def build_turn(unit, turn_id, clauses, pre_turn, semantic_coherence_score)
        mood_counts = clauses.map { |c| c.interpersonal.mood }.tally

        Core::Types::ConversationTurn.new(
          turn_id:,
          speaker: turn_speaker(unit),
          timestamp: unit.sent_at || Time.now,
          message_text: unit.text,
          clauses:,
          avg_tenor: mean(clauses.map { |c| c.interpersonal.tenor }),
          avg_modality: mean(clauses.map { |c| c.interpersonal.modality_weight }),
          dominant_mood: mood_counts.max_by { |_, count| count }&.first || "declarative",
          process_types: clauses.map { |c| c.ideational.process_type }.tally,
          participants: clauses.flat_map { |c| c.ideational.participants.map(&:text) }.uniq,
          tenor_shift: nil,
          topic_distribution: pre_turn&.topic_distribution,
          dominant_topic: pre_turn&.dominant_topic,
          semantic_coherence_score:
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private def unwrap(result, document_id)
        result.value_or { |failure| raise Error, "compile failed for #{document_id.inspect}: #{failure.inspect}" }
      end

      private def enqueue_review(source, unit, clauses, store)
        return unless store && @review_queue_repo

        entry = source.review_entry(unit:, clauses:)
        return unless entry

        @review_queue_repo.enqueue(document_id: unit.document_id, source_file: unit.document_id, **entry)
      end

      private def report_progress(turn, total, elapsed)
        return unless @on_progress

        defaulted = turn.clauses.count { |c| !Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(c.interpersonal.annotation_source) }
        @on_progress.call(
          turn_id: turn.turn_id, total:, speaker: turn.speaker,
          elapsed: elapsed.round(2), clause_count: turn.clauses.size,
          defaulted:, turn:
        )
      end

      # Superset of legacy's two independent detect_key_moments copies
      # (ConversationAnalyzer had modality_shift + deflation_anomaly on
      # top of what DocumentationAnalyzer computed) — deliberate
      # convergence, not a byte-exact preservation of either: the
      # conversation/ golden master (generated by legacy
      # ConversationAnalyzer) is the byte-exact gate this wording is
      # checked against; documentation/ is explicitly not.
      private def detect_key_moments(turns)
        moments = []
        turns.each_cons(2) { |prev, curr| moments.concat(shift_moments(prev, curr)) }
        turns.each { |curr| moments.concat(anomaly_moments(curr)) }
        moments
      end

      private def shift_moments(prev, curr)
        [tenor_shift_moment(prev, curr), modality_shift_moment(prev, curr)].compact
      end

      private def tenor_shift_moment(prev, curr)
        shift = (curr.avg_tenor - prev.avg_tenor).round(3)
        return nil unless shift.abs > 0.15

        direction = shift.positive? ? "increased" : "decreased"
        Core::Types::KeyMoment.new(
          turn_id: curr.turn_id, type: "tenor_shift", magnitude: shift,
          description: "Formality #{direction} dramatically (+#{shift}) between #{prev.speaker} and #{curr.speaker}"
        )
      end

      private def modality_shift_moment(prev, curr)
        shift = (curr.avg_modality - prev.avg_modality).round(3)
        return nil unless shift.abs > 0.3

        direction = shift.positive? ? "increased" : "decreased"
        Core::Types::KeyMoment.new(
          turn_id: curr.turn_id, type: "modality_shift", magnitude: shift,
          description: "Certainty #{direction} significantly (+#{shift}) in #{curr.speaker}'s response"
        )
      end

      private def anomaly_moments(curr)
        return [] unless curr.semantic_coherence_score
        return [] unless curr.semantic_coherence_score < 0.35

        is_deflation = %w[interrogative imperative].include?(curr.dominant_mood) ||
          curr.avg_modality < 0.4 || curr.avg_tenor < 0.4

        [is_deflation ? deflation_moment(curr) : semantic_anomaly_moment(curr)]
      end

      private def deflation_moment(curr)
        Core::Types::KeyMoment.new(
          turn_id: curr.turn_id, type: "deflation_anomaly", magnitude: curr.semantic_coherence_score,
          description: "Turn #{curr.turn_id} by #{curr.speaker} contains a semantically anomalous deflation move " \
            "(coherence: #{curr.semantic_coherence_score.round(3)}, mood: #{curr.dominant_mood}, " \
            "modality: #{curr.avg_modality.round(3)}, tenor: #{curr.avg_tenor.round(3)})"
        )
      end

      private def semantic_anomaly_moment(curr)
        Core::Types::KeyMoment.new(
          turn_id: curr.turn_id, type: "semantic_anomaly", magnitude: curr.semantic_coherence_score,
          description: "Turn #{curr.turn_id} by #{curr.speaker} is semantically anomalous relative to the " \
            "conversation baseline (coherence: #{curr.semantic_coherence_score.round(3)})"
        )
      end

      private def detect_example_passages(turns)
        [
          passage_for(turns.max_by(&:avg_tenor), "Most Formal", :avg_tenor,
            "Highest tenor (formality) score in the conversation"),
          passage_for(turns.min_by(&:avg_tenor), "Most Casual", :avg_tenor,
            "Lowest tenor score; uses informal register"),
          passage_for(turns.max_by(&:avg_modality), "Most Certain", :avg_modality,
            "Highest modality weight; assertive and definitive language"),
          passage_for(turns.min_by(&:avg_modality), "Most Hedged", :avg_modality,
            "Lowest modality weight; frequent use of hedging or uncertainty"),
        ].compact
      end

      private def passage_for(turn, label, value_method, reason)
        return nil unless turn

        Core::Types::ExamplePassage.new(label:, text: turn.message_text, speaker: turn.speaker,
          value: turn.public_send(value_method), reason:)
      end

      private def tenor_timeline(turns)
        turns.map do |turn|
          {
            turn_id: turn.turn_id,
            timestamp: turn.timestamp.iso8601,
            speaker: turn.speaker,
            tenor: turn.avg_tenor,
            tenor_shift: turn.tenor_shift,
          }
        end
      end

      private def field_evolution(turns)
        turns.map do |turn|
          {
            turn_id: turn.turn_id,
            timestamp: turn.timestamp.iso8601,
            dominant_process: turn.process_types.max_by { |_, count| count }&.first,
          }
        end
      end

      private def topic_evolution(turns)
        turns.filter_map do |turn|
          next unless turn.dominant_topic

          {
            turn_id: turn.turn_id,
            timestamp: turn.timestamp.iso8601,
            dominant_topic: turn.dominant_topic,
            topic_distribution: turn.topic_distribution,
          }
        end
      end

      private def generate_insights(turns, topic_labels)
        return [] if turns.empty?

        [tenor_trend_insight(turns), speaker_share_insight(turns)].compact + topic_insights(turns, topic_labels)
      end

      private def tenor_trend_insight(turns)
        tenors = turns.map(&:avg_tenor)
        trend = tenors.last - tenors.first
        if trend > 0.1
          "Conversation tenor increased by #{(trend * 100).round(1)}% (more formal/distant)"
        elsif trend < -0.1
          "Conversation tenor decreased by #{(trend.abs * 100).round(1)}% (more casual/close)"
        end
      end

      private def speaker_share_insight(turns)
        counts = turns.map(&:speaker).tally
        return nil unless counts.size > 1

        top = counts.max_by { |_, count| count }.first
        "#{top} contributed #{counts[top]} of #{turns.size} turns"
      end

      private def topic_insights(turns, topic_labels)
        return [] unless topic_labels && topic_labels.any?

        [
          "#{topic_labels.size} topics identified across the conversation",
          dominant_topic_insight(turns, topic_labels),
        ].compact
      end

      private def dominant_topic_insight(turns, topic_labels)
        dominant_topics = turns.filter_map(&:dominant_topic).tally
        return nil unless dominant_topics.any?

        top_topic = dominant_topics.max_by { |_, count| count }.first
        top_words = topic_labels[top_topic]&.first(3)&.join(", ") || "topic #{top_topic}"
        "Most prominent topic: #{top_words} (#{dominant_topics[top_topic]} turns)"
      end

      private def topic_k(topics) = topics.zero? ? nil : topics

      private def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    # rubocop:enable Metrics/ClassLength
  end
end
