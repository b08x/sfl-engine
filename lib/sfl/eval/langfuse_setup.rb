# frozen_string_literal: true

module SFL
  module Eval
    # Creates the score configs and annotation queues the evaluation relies on.
    # Scales and anchor text are the approved ones in
    # goals/narrative-nuance-evals/anchors.md (approved 2026-10-15); changing
    # them after labeling starts invalidates the gold set.
    class LangfuseSetup
      MOODS = %w[declarative interrogative imperative exclamative].freeze
      QUEUES = {
        "pass2-gold" => "Label mood and tenor on every clause; modality only where the queue item metadata says so",
        "judge-calibration" => "Score interpretive yield and recap ratio on the 8 calibration narratives",
      }.freeze

      TENOR_ANCHORS = "0: slang or clipped; .25: casual spoken; .5: neutral written; " \
        ".75: careful written, hedged or impersonal; 1: institutional or technical-legal"
      MODALITY_ANCHORS = "0: speculation; .25: possible, evidence-limited; .5: plain unmarked report; " \
        ".75: emphasized or expected; 1: beyond dispute, universal scope"
      YIELD_ANCHORS = "0: no supported mapping; 1: one supported mapping, no explanation; " \
        "2: two or more supported mappings, or one that states what the pattern shows; " \
        "3: mappings that together explain how roles or stance change across turns"
      RECAP_ANCHORS = "0: under 25% restatement; 1: 25-50%; 2: 50-75%; 3: over 75%"

      SCORE_CONFIGS = [
        {
          name: "mood",
          data_type: "CATEGORICAL",
          categories: MOODS.each_with_index.map { |label, value| { label:, value: } },
          description: "Grammatical mood of the clause. Rhetorical questions stay interrogative; hedged imperatives keep their grammatical mood.",
        },
        {
          name: "tenor",
          data_type: "NUMERIC",
          min_value: 0,
          max_value: 1,
          description: "Formality in steps of .25. #{TENOR_ANCHORS}",
        },
        {
          name: "modality",
          data_type: "NUMERIC",
          min_value: 0,
          max_value: 1,
          description: "Certainty in steps of .25. #{MODALITY_ANCHORS}",
        },
        {
          name: "interpretive_yield",
          data_type: "NUMERIC",
          min_value: 0,
          max_value: 3,
          description: "Per narrative section. #{YIELD_ANCHORS}",
        },
        {
          name: "recap_ratio",
          data_type: "NUMERIC",
          min_value: 0,
          max_value: 3,
          description: "Per narrative section. #{RECAP_ANCHORS}",
        },
      ].freeze

      Result = Struct.new(:configs, :queues, :manual_steps, keyword_init: true)

      # @param client [LangfuseClient]
      # @param log [#puts]
      def initialize(client:, log: $stderr)
        @client = client
        @log = log
      end

      # @return [Result] config names, queue names created or found, and UI steps
      #   the operator must perform when the API refuses queue creation
      def call
        configs = SCORE_CONFIGS.to_h { |spec| [spec[:name], @client.ensure_score_config(**spec)] }
        queues, manual = ensure_queues(configs)
        Result.new(configs: configs.keys, queues:, manual_steps: manual)
      end

      private def ensure_queues(configs)
        existing = @client.list_annotation_queues.to_h { |queue| [queue["name"], queue] }
        created = []
        manual = []
        QUEUES.each do |name, description|
          if existing.key?(name)
            created << name
            next
          end
          create_queue(name, description, configs, created, manual)
        end
        [created, manual]
      end

      private def create_queue(name, description, configs, created, manual)
        ids = configs.values.filter_map { |config| config["id"] }
        @client.create_annotation_queue(name:, description:, score_config_ids: ids)
        created << name
      rescue LangfuseClient::Error => e
        @log.puts("[WARN] queue #{name} not created through the API: #{e.message}")
        manual << "Create annotation queue '#{name}' in the Langfuse UI (Annotation Queues > New) " \
          "with description '#{description}' and attach all five score configs."
      end
    end
  end
end
