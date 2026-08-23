# frozen_string_literal: true

require "amatch"

module SFL
  module Core
    # Centralized registry for mood and theme_type classifications.
    # Eliminates redundancy across types, normalizers, and prompt configs.
    # rubocop:disable Metrics/ModuleLength -- two full classification tables (mood, theme_type) plus their
    # normalization logic belong together; splitting them would scatter one conceptual unit across files.
    module ClassificationRegistry
      # Fuzzy-match floor for the Jaro-Winkler fallback in .normalize.
      # Calibrated against live Pass 2 output: every observed real
      # near-miss scores >= 0.9378 against its intended target
      # ("subjective"→"subjunctive" 0.944, "imperitive"→"imperative"
      # 0.938, "interogative"→"interrogative" 0.985), while the best
      # garbage/unrelated term tops out at 0.809 ("performative"→
      # "imperative"; "infinitive"→"indicative" 0.802). 0.92 sits in
      # that gap with margin on both sides — raise it before ever
      # lowering it, since a false fuzzy match silently rewrites a
      # value while a miss merely falls through to the (warned)
      # default.
      FUZZY_THRESHOLD = 0.92

      # Below this length Jaro-Winkler scores inflate (and the prefix
      # bonus dominates), so short unknowns fall straight through to
      # the default rather than risking a spurious match.
      FUZZY_MIN_LENGTH = 4

      MOOD = {
        canonical: %w[declarative interrogative imperative exclamative indicative minor fragment].freeze,
        aliases: {
          "exclamatory" => "exclamative",
          "non-finite" => "fragment",
          "none" => "fragment",
          "vocative" => "minor",
          "question" => "interrogative",
          "questions" => "interrogative",
          "query" => "interrogative",
          "queries" => "interrogative",
          "elliptical" => "declarative",
          "elliptical_fragment" => "fragment",
          "nominal" => "fragment",
          "narrative" => "declarative",
          "continuative" => "declarative",
          "rhetorical_question" => "interrogative",
          "rhetorical question" => "interrogative",
          "modal" => "declarative",
          "exhortative" => "imperative",
          "conditional" => "declarative",
          "subjunctive" => "declarative",
          "subjective" => "declarative",
          "interjectional" => "minor",
          "interjection" => "minor",
          "neutral" => "declarative",
          "null" => "declarative",
          "n/a" => "declarative",
          "" => "declarative",
        }.freeze,
        transforms: [
          -> (val) { val.end_with?("_phrase") ? "fragment" : val },
          -> (val) { val.sub(/\s*\(.*\)\z/, "") },
        ].freeze,
        default: "declarative",
      }.freeze

      THEME_TYPE = {
        canonical: %w[
          unmarked
          marked
          interrogative
          imperative
          multiple
          topical
          simple
          existential
          clausal
          textual
          interjection
          interpersonal
          predicated
          predicator
          circumstantial
        ].freeze,
        aliases: {
          "topual" => "topical",
          "topical_unmarked" => "topical",
          "vocative" => "interpersonal",
          "process" => "predicator",
          "modal" => "interpersonal",
          "interjectional" => "interjection",
          "temporal" => "circumstantial",
          "spatial" => "circumstantial",
          "causal" => "circumstantial",
          "conditional" => "circumstantial",
          "concessive" => "circumstantial",
          "manner" => "circumstantial",
          "marking" => "marked",
          "fragment" => "unmarked",
          "heading" => "unmarked",
          "null" => "unmarked",
          "none" => "unmarked",
          "n/a" => "unmarked",
          "" => "unmarked",
        }.freeze,
        transforms: [
          lambda do |val|
            val = val.split("+").map(&:strip).find { |p| !p.empty? } || "" if val.include?("+")
            val = val.delete_prefix("theme_").delete_suffix("_theme").delete_suffix(" theme").strip
            if val.include?(">") || val.include?(",") || val.match?(/\band\b/) ||
                val.include?("-plus-") || (val.include?("_") && val != "topical_unmarked")

              parts = val.split(/[>,_]|\s+and\s+|-plus-/).map(&:strip).reject(&:empty?)
              val = "multiple" if parts.size > 1
            end
            val
          end,
        ].freeze,
        default: "unmarked",
      }.freeze

      # Precomputed fuzzy-match candidate pools (canonical values plus
      # alias keys, minus entries too short to match reliably) — frozen
      # constants rather than a lazily-built cache because normalize runs
      # per-clause on Pass 2's multi-threaded pool.
      FUZZY_CANDIDATES = {
        mood: (MOOD[:canonical] + MOOD[:aliases].keys)
          .reject { |c| c.length < FUZZY_MIN_LENGTH }.freeze,
        theme_type: (THEME_TYPE[:canonical] + THEME_TYPE[:aliases].keys)
          .reject { |c| c.length < FUZZY_MIN_LENGTH }.freeze,
      }.freeze

      # Normalizes a raw classification string to a canonical value.
      # Returns [canonical_value, status] where status is :exact,
      # :aliased, :fuzzy, or :unknown.
      def self.normalize(dimension, raw)
        config = dimension_config(dimension)
        val = raw.to_s.downcase.strip

        config[:transforms].each do |transform|
          val = transform.call(val)
          val = val.to_s.strip
        end

        if config[:canonical].include?(val)
          [val, :exact]
        elsif config[:aliases].key?(val)
          [config[:aliases][val], :aliased]
        elsif (fuzzy = fuzzy_lookup(dimension, config, val))
          [fuzzy, :fuzzy]
        else
          [config[:default], :unknown]
        end
      end

      # Returns a duplicate array of the canonical values.
      def self.canonical_values(dimension)
        dimension_config(dimension)[:canonical].dup
      end

      # Returns a formatted list suitable for LLM prompt/schema descriptions.
      def self.signature_description(dimension)
        vals = dimension_config(dimension)[:canonical]
        if vals.empty?
          ""
        elsif vals.size == 1
          vals.first
        else
          "#{vals[0...-1].join(', ')}, or #{vals.last}"
        end
      end

      # Last resort before defaulting: Jaro-Winkler the unknown value
      # against every canonical value and alias key, resolving through
      # the alias table when the best hit is an alias. Catches the long
      # tail of LLM near-misses (typos, adjectival forms, plural "s")
      # that previously each needed a hand-written alias entry after
      # showing up in a live run's WARNs.
      private_class_method def self.fuzzy_lookup(dimension, config, val)
        return nil if val.length < FUZZY_MIN_LENGTH

        matcher = Amatch::JaroWinkler.new(val)
        best, score = FUZZY_CANDIDATES[dimension.to_sym].map { |c| [c, matcher.match(c)] }.max_by(&:last)
        return nil if score < FUZZY_THRESHOLD

        config[:aliases].fetch(best, best)
      end

      private_class_method def self.dimension_config(dimension)
        case dimension.to_sym
        when :mood
          MOOD
        when :theme_type
          THEME_TYPE
        else
          raise ArgumentError, "Unknown dimension: #{dimension}"
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
