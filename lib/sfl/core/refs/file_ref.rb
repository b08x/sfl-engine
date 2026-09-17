# frozen_string_literal: true

require "dry/struct"

module SFL
  module Core
    module Refs
      # A reference to a file on a filesystem or in a git tree. Deliberately
      # not a path — #read provides the bytes, not File.read. The adapter
      # that created the ref is responsible for materializing content on
      # demand (File.read for filesystem, git cat-file for git).
      #
      # ImageSource is the one loader that needs a real path for its
      # vision-model call; its adapter materializes a temp path via
      # #path_hint (nil for non-filesystem origins).
      class FileRef < Dry::Struct
        # @return [String] basename without extension, e.g. "report"
        attribute :name, Types::String

        # @return [String] dot-prefixed lowercase extension, e.g. ".md"
        attribute :extension, Types::String

        # @return [String] opaque identity from the adapter — mtime+size for
        #   filesystem, blob SHA for git. Used for skip-if-unchanged.
        attribute :content_identity, Types::String

        # @return [Integer] file size in bytes
        attribute :size_bytes, Types::Integer

        # @return [Time, nil] modification time; nil for git (no mtime in tree)
        attribute :mtime, Types::Time.optional.default(nil)

        # @return [String] unique id for the source this ref came from —
        #   e.g. the filesystem root path or git repo URL
        attribute :source_id, Types::String

        # @return [String, nil] filesystem path if the ref was materialized
        #   from a real file; nil for git/other origins. ImageSource uses
        #   this for its vision-model call.
        attribute :path_hint, Types::String.optional.default(nil)

        # @param limit [Integer, nil] max bytes to read; nil = whole file
        # @return [String] file content (or first +limit+ bytes)
        def read(limit = nil)
          raise Loaders::Error, "FileRef has no path_hint — cannot read" unless path_hint

          limit ? File.read(path_hint, limit) : File.read(path_hint, encoding: "utf-8")
        end
      end
    end
  end
end
