# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
require "dspy"

module SFL
  module Analysis
    # Expands unstructured text (like .md transcripts) into one native JSONL
    # file under `dest_dir`, using an LLM to parse out the speaker turns dynamically.
    module DynamicFormatExpander
      class DynamicConversationSignature < DSPy::Signature
        description "Extract the conversation turns from the raw text transcript. Preserve exact message text without summarizing. If timestamps exist, include them. Identify speakers."

        class Turn < T::Struct
          const :name, String, description: "The name of the speaker."
          const :mes, String, description: "The message text."
          const :send_date, T.nilable(String), description: "Timestamp of the message, ISO8601 if available."
          const :is_user, T::Boolean, description: "True if the speaker is a human user, false if AI/System."
        end

        input do
          const :text, String, description: "Raw text transcript to parse"
        end

        output do
          const :turns, T::Array[Turn], description: "The sequence of conversation turns extracted from the text."
        end
      end

      module_function def expand(path, dest_dir:, lm:)
        text = File.read(path)

        warn "[INFO] dynamically expanding #{File.basename(path)} via LLM (this may take 15-60+ seconds)..."
        predictor = DSPy::Predict.new(DynamicConversationSignature).tap { |p| p.configure { |c| c.lm = lm } }
        result = predictor.call(text:)
        warn "[INFO] successfully expanded #{File.basename(path)}"

        parsed = result.to_h

        FileUtils.mkdir_p(dest_dir)

        title_slug = ChatExportExpander.slugify(File.basename(path, ".*"))

        out_path = File.join(dest_dir, "#{title_slug}-#{Digest::MD5.hexdigest(path)[0, 8]}.jsonl")

        File.open(out_path, "w") do |io|
          parsed[:turns].each do |turn|
            io.puts(JSON.dump(
              name: turn.fetch(:name),
              mes: turn.fetch(:mes),
              send_date: turn.fetch(:send_date),
              is_user: turn.fetch(:is_user)
            ))
          end
        end

        [{ path: out_path, source_type: "dynamic_format", label: title_slug }]
      end
    end
  end
end
