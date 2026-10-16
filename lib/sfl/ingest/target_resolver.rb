# frozen_string_literal: true

module SFL
  module Ingest
    # Turns a CLI argument or HTTP request body into a named source
    # descriptor so unsupported sources fail by name, not ENOENT
    # (SFL-ING-19).
    #
    # Rule order (first match wins):
    # 1. SCP-style git remote  — git@host:path
    # 2. https git URL        — https://… ending .git or known forge host
    # 3. file:// URL          — file:// path
    # 4. .git dir at/above    — path contains a .git directory
    # 5. directory            — File.directory?
    # 6. file                 — File.file?
    #
    # Future web/MCP adapters: add a new branch here plus a new adapter —
    # no change to CorpusSource, RoutingTable, or either driving adapter.
    class TargetResolver
      class UnresolvableTarget < ArgumentError
      end

      KNOWN_FORGE_HOSTS = %w[
        github.com
        gitlab.com
        bitbucket.org
        codeberg.org
        git.sr.ht
      ].freeze

      # @param arg [String] the raw target argument
      # @return [Hash] {type: :filesystem, root:} or {type: :git, repo:, ref:}
      # @raise [UnresolvableTarget] if no rule matches
      def self.call(arg)
        new(arg).resolve
      end

      def initialize(arg)
        @arg = arg
        @rules_tried = []
      end

      def resolve
        expanded = expand_path(@arg)

        rule("scp git remote") { match_scp_remote(expanded) } ||
          rule("https git URL") { match_https_git(expanded) } ||
          rule("file:// URL") { match_file_url(expanded) } ||
          rule(".git directory") { match_git_dir(expanded) } ||
          rule("directory") { match_directory(expanded) } ||
          rule("file") { match_file(expanded) } ||
          raise_unresolvable(expanded)
      end

      private

      def expand_path(arg)
        return arg unless arg.start_with?("~")

        File.expand_path(arg)
      end

      def rule(name)
        @rules_tried << name
        yield
      end

      def match_scp_remote(arg)
        return nil unless arg.start_with?("git@") && arg.include?(":")

        repo = arg
        { type: :git, repo:, ref: "HEAD" }
      end

      def match_https_git(arg)
        return nil unless arg.start_with?("https://", "http://")

        uri = begin
          URI.parse(arg)
        rescue URI::InvalidURIError
          return nil
        end
        return nil unless uri.host

        is_git = arg.end_with?(".git") ||
          KNOWN_FORGE_HOSTS.any? { |h| uri.host == h || uri.host.end_with?(".#{h}") }
        return nil unless is_git

        { type: :git, repo: arg, ref: "HEAD" }
      end

      def match_file_url(arg)
        return nil unless arg.start_with?("file://")

        path = arg.sub(%r{\Afile://}, "")
        path = expand_path(path) if path.start_with?("~")
        { type: :filesystem, root: path }
      end

      def match_git_dir(arg)
        # Only an existing local path can sit inside a repository. A string
        # such as "https://host/x" is relative to the cwd, so walking up from
        # it would reach "." and match the cwd's own .git.
        return nil unless File.exist?(arg)

        # Walk upward from the path looking for a .git directory
        path = arg
        loop do
          git_path = File.join(path, ".git")
          return { type: :git, repo: path, ref: "HEAD" } if File.directory?(git_path)

          parent = File.dirname(path)
          break if parent == path

          path = parent
        end
        nil
      end

      def match_directory(arg)
        return nil unless File.directory?(arg)

        { type: :filesystem, root: arg }
      end

      def match_file(arg)
        return nil unless File.file?(arg)

        { type: :filesystem, root: arg }
      end

      def raise_unresolvable(arg)
        raise UnresolvableTarget,
          "could not resolve target: #{arg.inspect}. " \
            "Rules tried: #{@rules_tried.join(', ')}. " \
            "Web and other non-filesystem/git sources are not supported in this phase."
      end
    end
  end
end
