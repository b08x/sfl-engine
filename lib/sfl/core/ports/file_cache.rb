# frozen_string_literal: true

require "fileutils"
require "json"

module SFL
  module Core
    module Ports
      # Real (file-backed) Cache adapter: one JSON file per key under
      # `cache_dir:`, so `Pipeline#annotate_with_cache` (via `--resume`)
      # can actually resume across separate process runs — the in-memory
      # Fake::Cache can't survive past one process, and Null::Cache never
      # stores anything at all.
      #
      # Deliberately NOT a port of legacy's PipelineCache
      # (storage/pipeline_cache.rb): this port's contract is already
      # simpler (opaque String keys, computed by Pipeline itself via
      # #cache_key_for — see Pipeline's class comment) rather than
      # document_id/clause-object-keyed, and Core::Wire already owns
      # struct<->JSON serialization, so there is no reconstruct_syntactic/
      # reconstruct_ideational/etc. to hand-write here — #write/#read are a
      # thin wrapper around Wire.dump/Wire.load_annotated_clause.
      class FileCache
        include Ports::Cache

        DEFAULT_CACHE_DIR = ".sfl-cache"

        def initialize(cache_dir: DEFAULT_CACHE_DIR)
          @cache_dir = cache_dir
          FileUtils.mkdir_p(@cache_dir)
        end

        # Reads each key's value directly from the same pass that decides
        # hit vs. miss — no second read of the hits afterward (the F10
        # contract Ports::Cache's own doc comment requires).
        # @param keys [Array<String>]
        # @return [[Hash<String, Core::Types::AnnotatedClause>, Array<String>]]
        def partition(keys)
          hits = {}
          misses = []
          keys.each do |key|
            value = read(key)
            value ? hits[key] = value : misses << key
          end
          [hits, misses]
        end

        # @param key [String]
        # @param value [Core::Types::AnnotatedClause]
        # @return [void]
        def write(key, value)
          File.write(path_for(key), JSON.generate(Wire.dump(value)))
          nil
        end

        private def read(key)
          path = path_for(key)
          return nil unless File.exist?(path)

          hash = JSON.parse(File.read(path), symbolize_names: true)
          Wire.load_annotated_clause(hash)
        rescue JSON::ParserError, KeyError, TypeError, ArgumentError, Dry::Struct::Error
          # A corrupted/unparseable/malformed cache entry is a miss, not a
          # crash — same defensive posture as legacy's PipelineCache#fetch.
          nil
        end

        private def path_for(key)
          File.join(@cache_dir, "#{key}.json")
        end
      end
    end
  end
end
