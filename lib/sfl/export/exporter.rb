# frozen_string_literal: true

require "fileutils"
require "securerandom"

module SFL
  module Export
    # Writes chosen sections' clauses to `<dir>/<collection>-<timestamp>.<ext>`
    # and records the export as a run of kind `export`.
    class Exporter
      WRITERS = { jsonl: JsonlWriter, markdown: MarkdownWriter }.freeze

      # Collection name used in the file name when the export spans several.
      MIXED = "mixed"

      # @param source [Core::Ports::BrowseSource]
      # @param run_log [Core::Ports::RunLog]
      # @param dir [String] output directory, created when missing
      # @param logger [Core::Ports::Logger]
      # @param clock [#call] returns the current Time
      # @param run_id [#call] returns a new run id
      def initialize(source:, run_log:, dir:, logger: Core::Ports::Null::Logger.new, clock: -> { Time.now },
        run_id: -> { SecureRandom.uuid }
      )
        @selection = ClauseSelection.new(source:)
        @run_log = run_log
        @dir = dir
        @logger = logger
        @clock = clock
        @run_id = run_id
      end

      # @param picks [Array<SectionPick>]
      # @param format [Symbol] :jsonl or :markdown
      # @return [Hash] `{path:, count:, run_id:}`
      # @raise [ArgumentError] for an unknown format
      def call(picks, format)
        writer = WRITERS.fetch(format) { raise ArgumentError, "unknown export format: #{format.inspect}" }
        records = @selection.resolve(picks)
        collection = collection_name(picks)
        run_id = @run_id.call
        @run_log.start(run_id:, kind: "export", collection:, total: records.size, pid: Process.pid)
        path = write(writer, records, collection)
        @run_log.advance(run_id, done: records.size, current_item: path)
        @run_log.finish(run_id, status: "finished")
        @logger.info("export written", path:, clauses: records.size, format:, run_id:)
        { path:, count: records.size, run_id: }
      rescue
        @run_log.finish(run_id, status: "failed") if run_id
        raise
      end

      private def write(writer, records, collection)
        FileUtils.mkdir_p(@dir)
        path = File.join(@dir, FileName.call(collection, @clock.call, writer::EXTENSION))
        File.open(path, "w") { |io| writer.call(records, io) }
        path
      end

      private def collection_name(picks)
        names = picks.map(&:collection).uniq
        names.one? ? names.first : MIXED
      end
    end
  end
end
