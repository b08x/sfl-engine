# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Adapters
        # The filesystem CorpusSource adapter. Walks a root path
        # (file or directory) and yields FileRef objects — the sole place
        # outside a loader that touches Dir.glob/File.file? (SFL-ING-17).
        #
        # Policy decisions that were previously scattered across the CLI's
        # kb_refs helper, the orchestrator's files method, and
        # KnowledgeBaseSource's directory globs are centralized here as
        # testable, named configuration:
        #
        # - Dot-directories (.git, .obsidian) excluded by default
        # - .gitignore patterns honored at each directory level
        # - Symlinks never followed (cycle-free by construction)
        # - Image files excluded unless include_images: true
        # - Vanished/permission-lost files skipped and counted, not raised
        # - Lazy depth-first enumeration via Dir.foreach + recursion
        class FilesystemCorpusSource
          include Ports::CorpusSource

          IMAGE_EXTENSIONS = Core::Loaders::ImageSource::SUPPORTED_EXTENSIONS
          DEFAULT_IGNORE_FILES = %w[.gitignore].freeze

          # @param root [String, Pathname] a file or directory to walk
          # @param include_images [Boolean] include image files (default false,
          #   forced true when root itself is an image file)
          # @param ignore_files [Array<String>] ignore-file names to honor at
          #   each directory level (default [".gitignore"])
          # @param exclude_dot_dirs [Boolean] exclude dot-directories (default true)
          def initialize(root, include_images: false, ignore_files: DEFAULT_IGNORE_FILES, exclude_dot_dirs: true)
            @root = root.to_s
            @exclude_dot_dirs = exclude_dot_dirs
            @ignore_files = ignore_files
            @include_images = include_images || image?(@root)
            @ignore_matcher = IgnoreMatcher.new(@ignore_files)
            @stats = {
              skipped_images: 0,
              skipped_dotdirs: 0,
              skipped_ignored: 0,
              skipped_vanished: 0,
              skipped_permission: 0,
            }
          end

          def each_ref
            return enum_for(:each_ref) unless block_given?

            if File.file?(@root)
              ref = build_ref(@root)
              yield ref if ref
              return
            end
            return unless File.directory?(@root)

            @ignore_matcher.load_directory(@root)
            walk(@root) do |path|
              ref = build_ref(path)
              yield ref if ref
            end
          end

          attr_reader :stats

          private def walk(dir, &)
            Dir.foreach(dir) do |entry|
              next if [".", ".."].include?(entry)

              path = File.join(dir, entry)
              handle_entry(path, entry, &)
            rescue Errno::ENOENT
              @stats[:skipped_vanished] += 1
            rescue Errno::EACCES
              @stats[:skipped_permission] += 1
            end
          end

          def handle_entry(path, entry, &)
            return if File.symlink?(path)

            if File.directory?(path)
              handle_directory(path, entry, &)
            elsif File.file?(path)
              handle_file(path, &)
            end
          rescue Errno::ENOENT
            @stats[:skipped_vanished] += 1
          rescue Errno::EACCES
            @stats[:skipped_permission] += 1
          end

          def handle_directory(path, entry, &)
            if @exclude_dot_dirs && entry.start_with?(".")
              @stats[:skipped_dotdirs] += 1
              return
            end

            @ignore_matcher.load_directory(path)
            if @ignore_matcher.ignored?(path, is_dir: true)
              @stats[:skipped_ignored] += 1
              return
            end

            walk(path, &)
          end

          def handle_file(path)
            if @ignore_matcher.ignored?(path, is_dir: false)
              @stats[:skipped_ignored] += 1
              return
            end

            if image?(path) && !@include_images
              @stats[:skipped_images] += 1
              return
            end

            yield path
          end

          def build_ref(path)
            stat = File.stat(path)
            Core::Refs::FileRef.new(
              name: File.basename(path, ".*"),
              extension: File.extname(path).downcase,
              content_identity: "#{stat.mtime.to_i}:#{stat.size}",
              size_bytes: stat.size,
              mtime: stat.mtime,
              source_id: @root,
              path_hint: path
            )
          rescue Errno::ENOENT
            @stats[:skipped_vanished] += 1
            nil
          rescue Errno::EACCES
            @stats[:skipped_permission] += 1
            nil
          end

          def image?(path)
            IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
          end

          # Reads .gitignore files at each directory level and applies
          # their patterns. Supports a practical subset of gitignore syntax:
          # - Simple glob patterns (e.g. *.tmp, node_modules/)
          # - Directory-anchored patterns (e.g. /build/)
          # - Negation (!pattern) is not supported (rarely needed for ingest)
          class IgnoreMatcher
            def initialize(ignore_file_names)
              @ignore_file_names = ignore_file_names
              @rules = []
            end

            def load_directory(dir)
              @ignore_file_names.each do |name|
                path = File.join(dir, name)
                next unless File.file?(path)

                patterns = File.readlines(path, chomp: true)
                patterns.each do |line|
                  line = line.strip
                  next if line.empty? || line.start_with?("#")

                  add_pattern(line, dir)
                end
              end
            end

            def ignored?(path, is_dir: false)
              relative = relative_to_root(path)
              @rules.any? { |rule| match?(rule, relative, is_dir) }
            end

            private def add_pattern(pattern, dir)
              # Patterns without a leading slash match anywhere at or below
              # the .gitignore's directory. Patterns with a leading slash
              # are anchored to the .gitignore's directory.
              anchored = pattern.start_with?("/")
              clean = anchored ? pattern[1..] : pattern
              dir_only = clean.end_with?("/")
              clean = clean.chomp("/") if dir_only

              @rules << {
                pattern: clean,
                base: dir,
                anchored:,
                dir_only:,
              }
            end

            def match?(rule, relative_path, is_dir)
              return false if rule[:dir_only] && !is_dir

              if rule[:anchored]
                match_anchored?(rule, relative_path)
              else
                match_unanchored?(rule, relative_path)
              end
            end

            def match_anchored?(rule, relative_path)
              base_relative = path_relative_to_base(relative_path, rule[:base])
              return false unless base_relative

              File.fnmatch?(rule[:pattern], base_relative, File::FNM_PATHNAME) ||
                File.fnmatch?(rule[:pattern], File.basename(base_relative), File::FNM_PATHNAME)
            end

            def match_unanchored?(rule, relative_path)
              # Match against the basename and against any suffix of the path
              File.fnmatch?(rule[:pattern], File.basename(relative_path), File::FNM_PATHNAME) ||
                path_components(relative_path).any? { |component| File.fnmatch?(rule[:pattern], component, File::FNM_PATHNAME) }
            end

            def path_relative_to_base(path, base)
              path = File.expand_path(path)
              base = File.expand_path(base)
              return nil unless path.start_with?("#{base}/")

              path[(base.length + 1)..]
            end

            def path_components(path)
              path.split("/")
            end

            def relative_to_root(path)
              File.expand_path(path)
            end
          end
        end
      end
    end
  end
end
