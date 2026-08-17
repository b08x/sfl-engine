# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
require "dspy"
require "tty-spinner"

module SFL
  module Analysis
    # Expands unstructured text (like .md transcripts) into one native JSONL
    # file under `dest_dir`, using an LLM to parse out the speaker turns dynamically.
    module DynamicFormatExpander
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

      module_function def expand(path, dest_dir:, lm:)
        FileUtils.mkdir_p(dest_dir)
        title_slug = ChatExportExpander.slugify(File.basename(path, ".*"))
        out_path = File.join(dest_dir, "#{title_slug}-#{Digest::MD5.hexdigest(path)[0, 8]}.jsonl")

        return cached_result(out_path, title_slug) if File.exist?(out_path)

        expand_and_write(path, dest_dir, lm, title_slug, out_path)
      end

      def self.cached_result(out_path, title_slug)
        warn "[INFO] skipping #{File.basename(out_path)} — already expanded"
        [{ path: out_path, source_type: "dynamic_format", label: title_slug }]
      end

      def self.expand_and_write(path, dest_dir, lm, title_slug, out_path)
        text = File.read(path)
        parsed = llm_expand(path, text, lm)

        write_raw_parsed(dest_dir, title_slug, parsed)
        debug_turns(parsed)
        write_jsonl(out_path, parsed)

        [{ path: out_path, source_type: "dynamic_format", label: title_slug }]
      end

      def self.llm_expand(path, text, lm)
        spinner = TTY::Spinner.new("[:spinner] [INFO] dynamically expanding #{File.basename(path)} via LLM...", format: :dots)
        spinner.auto_spin

        predictor = DSPy::Predict.new(DynamicConversationSignature).tap { |p| p.configure { |c| c.lm = lm } }
        result = predictor.call(text:)

        spinner.success("done!")
        warn "[INFO] successfully expanded #{File.basename(path)}"
        result.to_h
      end

      def self.write_raw_parsed(dest_dir, title_slug, parsed)
        raw_parsed_path = File.join(dest_dir, "#{title_slug}-raw_parsed.json")
        File.write(raw_parsed_path, JSON.pretty_generate(
          turns: parsed[:turns]&.map(&:serialize) || []
        ))
        warn "[DEBUG] Wrote raw parsed output to #{raw_parsed_path}"
      end

      def self.debug_turns(parsed)
        warn "[DEBUG] Extracted #{parsed[:turns]&.size || 0} turns:"
        parsed[:turns]&.each_with_index do |turn, i|
          warn "  [#{i}] #{turn.name}: #{turn.mes.to_s[0..50]}..."
        end
      end

      def self.write_jsonl(out_path, parsed)
        File.open(out_path, "w") do |io|
          parsed[:turns].each do |turn|
            io.puts(JSON.dump(
              name: turn.name || "Unknown Speaker",
              mes: turn.mes || "",
              send_date: turn.send_date,
              is_user: turn.is_user || false
            ))
          end
        end
      end
    end
  end
end
