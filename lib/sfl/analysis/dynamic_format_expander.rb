# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
require "dry/monads"
require "dspy"
require "tty-spinner"

module SFL
  module Analysis
    # Expands unstructured text (like .md transcripts) into one native JSONL
    # file under `dest_dir`, using an LLM to parse out the speaker turns dynamically.
    #
    # The LLM's parse is NOT trusted. Everything the model returns crosses a
    # validation/normalization boundary (`normalize_parsed`) before anything
    # downstream — the raw_parsed sidecar, the debug log, the JSONL writer —
    # is allowed to see it. The boundary lives on the parse side rather than
    # the write side deliberately: putting it at the write step would leave
    # every other consumer of `parsed` (and every future one) reading dirty
    # text, which is exactly how the corrupted `output/steve01` run happened.
    #
    # Two distinct model-contract violations are handled, differently:
    #
    #   * double-encoded message bodies (literal two-character `\n` sequences
    #     and zero real newlines) — mechanically recoverable, so they are
    #     decoded, counted, logged at warn, and persisted into the sidecar's
    #     `anomalies` block. A run that needed repair is never indistinguishable
    #     from a clean one.
    #   * a turn whose body carries another speaker's markdown header — NOT
    #     recoverable. The model failed to segment the transcript, so the turn's
    #     `name`/`is_user`/`send_date` are attached to text that is partly
    #     somebody else's. This fails the expansion loudly, naming the offending
    #     turns. It is deliberately not auto-split: splitting would mean this
    #     module re-implements the segmentation the model was asked to do, and
    #     would have to invent a speaker, timestamp, and is_user flag for the
    #     fabricated second half — producing plausible-looking attribution that
    #     is still wrong, i.e. the same silent-fallback failure mode documented
    #     at llm/engine.rb:109. A hard failure is re-runnable; bad attribution
    #     baked into speaker profiles is not detectable after the fact.
    # rubocop:disable Metrics/ModuleLength -- one boundary (parse -> validate/normalize -> write)
    # already decomposed into single-purpose methods; the length is the sum of those steps plus
    # the DSPy signature that has to live alongside them, not one long method.
    module DynamicFormatExpander
      extend Dry::Monads[:result]

      # Raised when the LLM's parse violates the expander's contract in a way
      # that cannot be mechanically repaired.
      class ContractViolation < StandardError; end

      # A message body validated and normalized at the parse boundary.
      NormalizedTurn = Data.define(:name, :mes, :send_date, :is_user)

      # Markdown ATX header line, capturing its label text.
      HEADER_LINE = /^[ \t]{0,3}\#{1,6}[ \t]*(?<label>\S.*?)[ \t]*$/
      # One or more literal backslashes immediately before a line break —
      # markdown's hard-break escape, meaningless to linguistic analysis.
      HARD_BREAK = /\\+\n/
      # Leading blockquote markers, however deeply nested.
      BLOCKQUOTE = /^[ \t]*(?:>[ \t]?)+/

      class DynamicConversationSignature < DSPy::Signature
        description "Extract the conversation turns from the raw text transcript. Preserve exact message text without summarizing. If timestamps exist, include them. Identify speakers."

        class Turn < T::Struct
          const :name, T.nilable(String), default: "Unknown Speaker", description: "The name of the speaker."
          const :mes, T.nilable(String), default: "", description: "The message text."
          const :send_date, T.nilable(String), default: nil, description: "Timestamp of the message, ISO8601 if available."
          const :is_user, T.nilable(T::Boolean), default: false, description: "True if the speaker is a human user, false if AI/System."
        end

        input do
          const :text, String, description: "Raw text transcript to parse"
        end

        output do
          const :turns, T::Array[Turn], description: "The sequence of conversation turns extracted from the text."
        end
      end

      module_function def expand(path, dest_dir:, lm:, logger: Core::Ports::StderrLogger.new)
        FileUtils.mkdir_p(dest_dir)
        title_slug = ChatExportExpander.slugify(File.basename(path, ".*"))
        out_path = File.join(dest_dir, "#{title_slug}-#{Digest::MD5.hexdigest(path)[0, 8]}.jsonl")

        return cached_result(out_path, title_slug, logger) if File.exist?(out_path)

        expand_and_write(path, dest_dir, lm, title_slug, out_path, logger)
      end

      def self.cached_result(out_path, title_slug, logger)
        logger.info("skipping #{File.basename(out_path)} — already expanded")
        [{ path: out_path, source_type: "dynamic_format", label: title_slug }]
      end

      # @raise [ContractViolation] when the model's parse cannot be trusted
      # rubocop:disable Metrics/ParameterLists -- every argument is already derived by #expand
      # (slug and out_path are computed there so the cache check can short-circuit); recomputing
      # them here would duplicate the naming rule in two places.
      def self.expand_and_write(path, dest_dir, lm, title_slug, out_path, logger)
        text = File.read(path)
        parsed = llm_expand(path, text, lm, logger)

        turns, anomalies = normalize_parsed(parsed, logger)
          .value_or { |failure| raise ContractViolation, describe_failure(File.basename(path), failure) }

        write_raw_parsed(dest_dir, title_slug, turns, anomalies, logger)
        debug_turns(turns, logger)
        write_jsonl(out_path, turns)

        [{ path: out_path, source_type: "dynamic_format", label: title_slug }]
      end
      # rubocop:enable Metrics/ParameterLists

      def self.describe_failure(basename, (code, detail))
        "#{basename}: LLM parse rejected (#{code}) — #{Array(detail).join('; ')}"
      end

      def self.llm_expand(path, text, lm, logger)
        spinner = TTY::Spinner.new("[:spinner] [INFO] dynamically expanding #{File.basename(path)} via LLM...", format: :dots)
        spinner.auto_spin

        predictor = DSPy::Predict.new(DynamicConversationSignature).tap { |p| p.configure { |c| c.lm = lm } }
        result = predictor.call(text:)

        spinner.success("done!")
        logger.info("successfully expanded #{File.basename(path)}")
        result.to_h
      end

      # The validation boundary. Nothing downstream of this method ever sees
      # the model's raw output.
      #
      # Every problem across every turn is collected before failing, rather than
      # short-circuiting on the first one: an operator re-running a broken
      # expansion needs the whole list, and a decode failure early in the
      # transcript must not hide a speaker-attribution violation later in it.
      #
      # @return [Dry::Monads::Result] Success([Array<NormalizedTurn>, Hash])
      #   or Failure([Symbol, Array<String>])
      def self.normalize_parsed(parsed, logger)
        raw = Array(parsed[:turns])
        return Failure([:empty_parse, ["model returned no turns"]]) if raw.empty?

        anomalies = { double_escaped_turns: 0, total_turns: raw.size }
        errors = []
        turns = raw.each_with_index.map do |turn, index|
          build_turn(turn, decode_body(turn.mes.to_s, index, anomalies, errors))
        end
        violations = speaker_violations(turns)
        return Failure(collect_failure(violations, errors)) if violations.any? || errors.any?

        report_anomalies(anomalies, logger)
        Success([turns, anomalies])
      end

      # Speaker attribution outranks escape damage: a mis-attributed turn poisons
      # speaker profiles, while a bad escape only poisons tokens.
      def self.collect_failure(violations, errors)
        code = violations.any? ? :speaker_attribution : errors.first.first
        [code, violations + errors.map(&:last)]
      end

      def self.build_turn(turn, body)
        NormalizedTurn.new(
          name: turn.name.to_s.strip.empty? ? "Unknown Speaker" : turn.name.strip,
          mes: scrub_markdown(body),
          send_date: turn.send_date,
          is_user: turn.is_user || false
        )
      end

      # Records any escape problem in `errors` and returns the best available
      # body: an undecodable body is still scanned for foreign speaker headers,
      # since those survive the escaping intact.
      #
      # @return [String]
      def self.decode_body(text, index, anomalies, errors)
        literal = text.scan("\\n").size
        return text if literal.zero?

        if text.include?("\n")
          errors << [
            :mixed_escape,
            "turn #{index}: #{literal} literal \\n sequences mixed with real newlines — cannot be safely decoded",
          ]
          return text
        end

        anomalies[:double_escaped_turns] += 1
        json_unescape(text) || begin
          errors << [
            :undecodable_escape,
            "turn #{index}: body is double-escaped but is not a decodable JSON string",
          ]
          # Not a repair — this turn has already failed and the whole expansion
          # is rejected either way. Splitting the literal escapes into real lines
          # only so the structural checks below can still see line-anchored
          # markdown and report every problem with this turn, not just the first.
          text.gsub("\\n", "\n")
        end
      end

      def self.json_unescape(text)
        JSON.parse(%("#{text}"))
      rescue JSON::ParserError
        nil
      end

      def self.scrub_markdown(text)
        text.gsub("\r\n", "\n")
          .gsub(HARD_BREAK, "\n")
          .gsub(BLOCKQUOTE, "")
          .gsub(/[ \t]+$/, "")
      end

      # A turn body carrying a markdown header that names a *different*
      # speaker means the model merged two turns into one.
      def self.speaker_violations(turns)
        speakers = turns.map(&:name).uniq
        turns.each_with_index.filter_map do |turn, index|
          foreign = foreign_headers(turn, speakers)
          next if foreign.empty?

          "turn #{index} is attributed to #{turn.name.inspect} but its body contains " \
            "header(s) for #{foreign.map(&:inspect).join(', ')}"
        end
      end

      def self.foreign_headers(turn, speakers)
        turn.mes.scan(HEADER_LINE).flatten
          .filter_map { |label| speaker_named_in(label, speakers) }
          .reject { |name| name.casecmp?(turn.name) }
          .uniq
      end

      def self.speaker_named_in(label, speakers)
        words = label.gsub(/[^[[:alnum:]]]+/, " ").split
        speakers.find { |speaker| words.any? { |word| word.casecmp?(speaker) } }
      end

      def self.report_anomalies(anomalies, logger)
        return if anomalies[:double_escaped_turns].zero?

        logger.warn(
          "model-contract violation: #{anomalies[:double_escaped_turns]}/#{anomalies[:total_turns]} " \
            "turns arrived double-escaped and were decoded at the parse boundary"
        )
      end

      def self.write_raw_parsed(dest_dir, title_slug, turns, anomalies, logger)
        raw_parsed_path = File.join(dest_dir, "#{title_slug}-raw_parsed.json")
        File.write(raw_parsed_path, JSON.pretty_generate(
          anomalies:,
          turns: turns.map(&:to_h)
        ))
        logger.debug("wrote raw parsed output to #{raw_parsed_path}")
      end

      def self.debug_turns(turns, logger)
        logger.debug("extracted #{turns.size} turns:")
        turns.each_with_index do |turn, i|
          logger.debug("  [#{i}] #{turn.name}: #{turn.mes.to_s[0..50]}...")
        end
      end

      def self.write_jsonl(out_path, turns)
        File.open(out_path, "w") do |io|
          turns.each { |turn| io.puts(JSON.dump(turn.to_h)) }
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
