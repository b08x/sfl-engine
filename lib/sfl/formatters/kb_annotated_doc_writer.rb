# frozen_string_literal: true

require "fileutils"

module SFL
  module Formatters
    # Writes one annotated Markdown file per source document (grouping
    # KnowledgeArtifacts that share a source_file — a document with
    # multiple headings, or a text pass plus an image pass, produces more
    # than one artifact for the same file). Opt-in via `--annotated` on
    # `knowledge-base`: unlike the CSV/JSON/MD migration report (one trio
    # for the whole batch), this can be one file per source document.
    module KBAnnotatedDocWriter
      # @return [Array<String>] paths written, one per source document
      module_function def write(result, output_dir)
        dir = File.join(output_dir, "annotated")
        FileUtils.mkdir_p(dir)

        used_names = Hash.new(0)

        # group_by preserves first-seen order of source_file, and within
        # each group the artifacts keep the analyzer's original ordering
        # (artifact_id ascending == document order), so concatenation
        # matches the source document's own structure.
        result.artifacts.group_by(&:source_file).map do |source_file, artifacts|
          path = File.join(dir, unique_filename_for(source_file, used_names))
          File.write(path, render_document(artifacts))
          path
        end
      end

      module_function def render_document(artifacts)
        first = artifacts.first
        sections = artifacts.map { |a| KBAnnotatedDocFormatter.new(a).render }

        "#{<<~MD.rstrip}\n"
          # #{first.title}

          **Source**: `#{first.source_file}`

          ---

          #{sections.join("\n---\n\n")}
        MD
      end

      module_function def filename_for(source_file)
        slug = File.basename(source_file, ".*")
          .downcase
          .gsub(/[^a-z0-9]+/, "-")
          .gsub(/^-+|-+$/, "")
        slug.empty? ? "untitled" : slug
      end

      # Different source directories can share a basename (two
      # "README.md" files) — disambiguate with a numeric suffix rather
      # than silently overwriting one artifact's output with another's.
      module_function def unique_filename_for(source_file, used_names)
        base = filename_for(source_file)
        count = used_names[base]
        used_names[base] += 1
        count.zero? ? "#{base}.md" : "#{base}-#{count + 1}.md"
      end
    end
  end
end
