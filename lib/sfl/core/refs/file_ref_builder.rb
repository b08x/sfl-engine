# frozen_string_literal: true

module SFL
  module Core
    module Refs
      # Utility for building a FileRef from a filesystem path. Used by
      # call sites that still work with raw paths (ChatExportExpander, the
      # orchestrator, the CLI) until the CorpusSource adapter (SFL-ING-17)
      # takes over enumeration entirely.
      module FileRefBuilder
        # @param path [String, Pathname] a real filesystem path, relative or absolute;
        #   path_hint is always the expanded absolute path, so every spelling of one
        #   file keys the same document
        # @param source_id [String] the source this ref belongs to
        # @return [FileRef]
        module_function def call(path, source_id: path.to_s)
          full = File.expand_path(path.to_s)
          stat = File.stat(full)
          basename = File.basename(full, ".*")
          ext = File.extname(full).downcase

          FileRef.new(
            name: basename,
            extension: ext,
            content_identity: "#{stat.mtime.to_i}:#{stat.size}",
            size_bytes: stat.size,
            mtime: stat.mtime,
            source_id:,
            path_hint: full
          )
        end
      end
    end
  end
end
