# frozen_string_literal: true

require "digest"

module SFL
  module Core
    module Loaders
      # Derives the section id prefix a loader puts before `#`.
      #
      # A ref with a path_hint gets its basename plus the first 8 hex digits
      # of the SHA-256 of that path (the unit's document_key), for example
      # "README-3f9a1c2e". Two files that share a basename (a/README.md and
      # b/README.md, or notes.md and notes.txt) therefore get different
      # section ids, inside one ingest and across collections, and the same
      # file gets the same ids on every re-ingest. A ref with no path_hint
      # keeps its bare basename, which is then also its document_key.
      module FileId
        DIGEST_LENGTH = 8

        # @param ref [Refs::FileRef]
        # @return [String]
        module_function def call(ref)
          path = ref.path_hint
          return ref.name unless path

          "#{ref.name}-#{Digest::SHA256.hexdigest(path)[0, DIGEST_LENGTH]}"
        end
      end
    end
  end
end
