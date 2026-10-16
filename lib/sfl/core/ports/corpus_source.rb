# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Origin-of-bytes port: the abstract source of files to ingest. The
      # orchestrator asks a CorpusSource for Refs and reads their content
      # through #read, never touching the filesystem directly — so git,
      # archives, or remote sources become adapter swaps, not orchestrator
      # edits (SFL-ING-16).
      #
      # A Ref is deliberately not a path: it exposes #read, #name,
      # #extension, #content_identity, #size_bytes, #mtime, and #source_id.
      # FileRef (lib/sfl/core/refs/file_ref.rb) is the filesystem/git
      # implementation; non-file origins (SQLite rows, HTTP responses)
      # supply their own.
      module CorpusSource
        # @yield [Object] a Ref (FileRef, RowRef, etc.) — lazy, one at a time
        # @return [Enumerator] if no block given
        def each_ref
          raise NotImplementedError, "#{self.class} must implement #each_ref"
        end

        # @return [Enumerator] built on #each_ref when no block is given
        def refs
          each_ref.to_a
        end

        # @return [Hash] adapter-level exclusion counts (e.g.
        #   { skipped_dotdirs: 3, skipped_ignored: 12 }), default {} — so
        #   total_seen doesn't lie about silently-filtered refs.
        def stats
          {}
        end
      end
    end
  end
end
