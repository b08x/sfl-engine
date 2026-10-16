# frozen_string_literal: true

require "json"

module SFL
  module Eval
    # Rewrites a NotebookLM caption transcript (one JSON object per caption with
    # "speaker" and "text") into the native chat shape the conversation loader
    # accepts ("name" and "mes"). The source file is read, never modified.
    module NotebooklmConverter
      # @param source [String] NotebookLM caption .jsonl
      # @param dest [String] native .jsonl to write
      # @return [Integer] number of lines written
      module_function def call(source, dest)
        count = 0
        File.open(dest, "w") do |out|
          File.foreach(source) do |line|
            next if line.strip.empty?

            row = JSON.parse(line)
            out.puts(JSON.dump(name: row.fetch("speaker"), mes: row.fetch("text"), is_user: false))
            count += 1
          end
        end
        count
      end
    end
  end
end
