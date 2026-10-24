# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Ingests JSON records files through a section registry, one file at a
      # time. Each file's units are written inside one registry transaction, so
      # a file that fails leaves no unit behind.
      #
      # #call is the batch seam. It returns:
      #   { ingested: Integer, processed: Integer, failed: [{file:, byte_offset:, reason:}],
      #     redundant: [{file:, byte_offset:, reason:}],
      #     skipped: [{file:, record_index:, reason:}], stale_removed: Integer }
      # ingested counts intact files; processed counts the units written by them.
      # A failed file whose every conversation uuid also appears in an intact
      # file of the same batch moves to redundant, with a warning, and is not
      # failed. A truncated file with a record that cannot be read is never
      # redundant, because its uuids are not all known.
      #
      # After every file is written, each document an intact file holds is
      # reconciled once: its stored sections that the run did not write are
      # removed. A document named by a failed file is not reconciled, so its
      # sections keep their previous state. stale_removed counts those sections.
      class JsonRecordsBatch
        REDUNDANT = "redundant_with_intact_file"

        # @param registry_factory [#call] returns a fresh Core::Ports::SectionRegistry for each file
        # @param logger [Core::Ports::Logger]
        def initialize(registry_factory:, logger: Core::Ports::Null::Logger.new)
          @registry_factory = registry_factory
          @logger = logger
        end

        # Ingests one file as a single run. A failure raises, with nothing from the file kept.
        # @return [JsonRecordsSource] the source, holding its document_keys and skipped
        # @raise [JsonRecordsSource::Failure]
        def ingest_one(ref)
          source = JsonRecordsSource.new(ref, logger: @logger)
          write(@registry_factory.call, source)
          source
        end

        # @param refs [Array<SFL::Core::Refs::FileRef>] processed in the order given
        # @return [Hash] the run summary described in the class comment
        def call(refs)
          outcomes = refs.map { |ref| outcome(ref) }
          intact = outcomes.select { |outcome| outcome[:failure].nil? }
          known = intact.flat_map { |outcome| outcome[:keys] }.to_set
          failed, redundant = settle(outcomes.reject { |outcome| outcome[:failure].nil? }, known)
          processed = intact.sum { |outcome| outcome[:units] }
          stale_removed = reconcile(intact, failed_keys(outcomes, known))
          { ingested: intact.size, processed:, failed:, redundant:, skipped: skipped(outcomes), stale_removed: }
        end

        private def outcome(ref)
          source = JsonRecordsSource.new(ref, logger: @logger)
          registry = @registry_factory.call
          units = write(registry, source)
          {
            file: file_name(ref),
            keys: source.document_keys,
            skipped: source.skipped,
            units:,
            written: registry.written,
            failure: nil,
          }
        rescue JsonRecordsSource::Failure => e
          {
            file: file_name(ref),
            keys: determinable_keys(source, e),
            skipped: source.skipped,
            units: 0,
            failure: { file: file_name(ref), byte_offset: e.byte_offset, reason: e.reason },
          }
        end

        # Returns the uuids of a failed file when they are all known, else nil.
        # Only a truncation can leave the file's uuids fully known, because
        # the file ends and no record is unread.
        private def determinable_keys(source, failure)
          return nil unless failure.reason == "truncated"
          return source.document_keys if failure.partial.nil?

          key = JsonRecordsSource::PartialKey.call(failure.partial)
          key && (source.document_keys + [key])
        end

        private def settle(failed_outcomes, known)
          failed = []
          redundant = []
          failed_outcomes.each do |outcome|
            entry = outcome[:failure]
            if redundant?(outcome[:keys], known)
              @logger.warn("json file skipped, every uuid is in an intact file", component: JsonRecordsSource::COMPONENT,
                file: entry[:file], byte_offset: entry[:byte_offset], reason: REDUNDANT)
              redundant << entry.merge(reason: REDUNDANT)
            else
              @logger.error("json file failed", component: JsonRecordsSource::COMPONENT, file: entry[:file],
                byte_offset: entry[:byte_offset], reason: entry[:reason])
              failed << entry
            end
          end
          [failed, redundant]
        end

        private def redundant?(keys, known) = !keys.nil? && !keys.empty? && keys.all? { |key| known.include?(key) }

        # The document keys of failed files that are not redundant. Their documents are never reconciled.
        # A failed file whose keys are not determinable adds nothing here.
        private def failed_keys(outcomes, known)
          outcomes
            .select { |outcome| outcome[:failure] && !redundant?(outcome[:keys], known) }
            .flat_map { |outcome| outcome[:keys] || [] }
        end

        # Reconciles once per run. Each document an intact file holds is
        # reconciled with the section ids the run wrote for it.
        # @return [Integer] sections removed
        private def reconcile(intact, failed_keys)
          written = Hash.new { |hash, key| hash[key] = [] }
          intact.each do |outcome|
            outcome[:keys].each { |key| written[key] }
            outcome[:written].each { |key, ids| written[key].concat(ids) }
          end
          documents = written.except(*failed_keys)
          return 0 if documents.empty?

          @registry_factory.call.reconcile(documents)
        end

        private def skipped(outcomes)
          outcomes.flat_map { |outcome| outcome[:skipped].map { |entry| entry.merge(file: outcome[:file]) } }
        end

        # @return [Integer] units written
        private def write(registry, source)
          units = 0
          registry.transaction do
            source.each_unit do |unit|
              registry.register(unit, 0)
              units += 1
            end
          end
          units
        end

        private def file_name(ref) = JsonRecordsSource::SafeText.line(File.basename(ref.path_hint.to_s))
      end
    end
  end
end
