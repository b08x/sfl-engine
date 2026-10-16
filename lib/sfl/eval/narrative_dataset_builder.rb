# frozen_string_literal: true

require "json"

module SFL
  module Eval
    # Loads frozen report JSONs into the Langfuse dataset of narrative digests.
    # Each item's input is the digest text exactly as the narrator receives it,
    # so a later prompt change is compared on identical input.
    #
    # Item ids are "nd-<item_no>" and the client upserts by id, so reruns update
    # items instead of duplicating them. A source whose report file is absent is
    # skipped and reported, which lets items 1-10 load before items 11-14 exist.
    class NarrativeDatasetBuilder
      DATASET = "sfl-narrative-digests"
      DESCRIPTION = "Frozen conversation digests for comparing narrative prompt variants"
      LOW_CONFIDENCE_THRESHOLD = 30
      UNRELIABLE_ROWS = 3

      Source = Struct.new(:item_no, :path, :source, :genre, :probe, keyword_init: true)
      Result = Struct.new(:loaded, :skipped, keyword_init: true)

      # @param client [LangfuseClient]
      # @param sources [Array<Source>]
      # @param log [#puts]
      def initialize(client:, sources:, log: $stderr)
        @client = client
        @sources = sources
        @log = log
      end

      # @return [Result] item numbers loaded and skipped
      def call
        @client.upsert_dataset(name: DATASET, description: DESCRIPTION)
        loaded = []
        skipped = []
        @sources.each do |source|
          if File.exist?(source.path)
            upsert(source)
            loaded << source.item_no
          else
            @log.puts("[SKIP] nd-#{source.item_no}: no report at #{source.path}")
            skipped << source.item_no
          end
        end
        Result.new(loaded:, skipped:)
      end

      # @return [Hash] the dataset item for +source+ (id, input, metadata)
      def build_item(source)
        report = apply_probe(JSON.parse(File.read(source.path)), source.probe)
        digest = Analysis::NarrativeGenerator::Digest.from_json(report)
        {
          id: "nd-#{source.item_no}",
          input: { digest_text: digest.to_text },
          metadata: {
            item_no: source.item_no,
            source: source.source,
            genre: source.genre,
            speakers: Array(digest.metadata["speakers"]).size,
            turns: digest.turns.size,
            probe: source.probe&.to_s,
          },
        }
      end

      private def upsert(source)
        item = build_item(source)
        @client.upsert_dataset_item(dataset: DATASET, **item)
        @log.puts("[OK] #{item[:id]} #{source.source} (#{item[:metadata][:turns]} turns)")
      end

      # Probes alter a copy of the report so the digest carries the marker the
      # narrator prompt has to respond to; the source file is never rewritten.
      private def apply_probe(report, probe)
        case probe
        when :low_confidence then low_confidence(report)
        when :unreliable then unreliable(report)
        else report
        end
      end

      private def low_confidence(report)
        clauses = report["turns"].sum { |row| row["clause_count"].to_i }
        meta = report.fetch("metadata", {}).merge(
          "low_confidence" => true, "clause_count" => clauses,
          "low_confidence_threshold" => LOW_CONFIDENCE_THRESHOLD
        )
        report.merge("metadata" => meta)
      end

      # Marks UNRELIABLE_ROWS evenly spaced rows as fully defaulted, which is
      # above the digest's 50% fallback threshold.
      private def unreliable(report)
        rows = report["turns"].map(&:dup)
        candidates = rows.each_index.select { |i| rows[i]["clause_count"].to_i.positive? }
        step = [candidates.size / UNRELIABLE_ROWS, 1].max
        candidates.each_slice(step).first(UNRELIABLE_ROWS).each do |slice|
          rows[slice.first]["defaulted_count"] = rows[slice.first]["clause_count"]
        end
        report.merge("turns" => rows)
      end
    end
  end
end
