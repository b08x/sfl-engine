# frozen_string_literal: true

require "fileutils"

module SFL
  module Formatters
    # Writes a KnowledgeBaseReport to the standard CSV/JSON/Markdown trio.
    module KBReportWriter
      FORMATTERS = {
        csv: ["kb_migration.csv", KBCsvFormatter],
        json: ["kb_migration.json", KBJsonFormatter],
        markdown: ["kb_migration.md", KBMarkdownFormatter],
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
