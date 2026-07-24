# frozen_string_literal: true

require "fileutils"

module SFL
  module Formatters
    # Writes an AnalysisResult to the standard CSV/JSON/Markdown trio.
    module ReportWriter
      FORMATTERS = {
        csv: ["conversation_analysis.csv", CSVFormatter],
        json: ["conversation_analysis.json", JSONFormatter],
        markdown: ["conversation_analysis.md", MarkdownFormatter],
      }.freeze

      # @return [Hash{Symbol => String}] format => written file path
      module_function def write(result, output_dir)
        FileUtils.mkdir_p(output_dir)

        FORMATTERS.to_h do |format, (filename, formatter_class)|
          path = File.join(output_dir, filename)
          formatter_class.new(result).write_to(path)
          [format, path]
        end
      end
    end
  end
end
