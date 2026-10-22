# frozen_string_literal: true

module SFL
  module Dashboard
    # What the foreground dashboard shows, as one immutable value. Every
    # event method returns a new State; Board holds the current one.
    #
    # Progress arrives as ProgressSink calls (see Sink): each #start opens a
    # document whose sections (turns or artifacts) are then counted by
    # #advance. A document is done when all its sections are.
    #
    # - `documents_total`: documents the run expects, nil when unknown
    # - `doc_total`, `doc_done`: sections of the document in progress
    # - `log`: the newest LOG_LIMIT log lines, oldest first
    # - `outcome`: nil while running, then "finished", "interrupted" or "failed"
    State = Data.define(
      :run_id, :kind, :collection, :models, :started_at, :now,
      :documents_total, :documents_started, :documents_done, :doc_total, :doc_done,
      :sections_total, :sections_done, :clauses, :defaulted, :failures, :backoffs,
      :current_item, :log, :stopping, :outcome
    ) do
      # @param models [Array<String>] "task provider/model" per task
      # @param documents [Integer, nil] documents the run expects
      # @param now [Time]
      def self.initial(run_id:, kind:, collection:, models:, documents:, now:)
        new(
          run_id:, kind:, collection:, models:, started_at: now, now:,
          documents_total: documents, documents_started: 0, documents_done: 0, doc_total: 0, doc_done: 0,
          sections_total: 0, sections_done: 0, clauses: 0, defaulted: 0, failures: 0, backoffs: 0,
          current_item: nil, log: [], stopping: false, outcome: nil
        )
      end

      # @param total [Integer] sections in the document that starts
      def start(total)
        return self unless total.positive?

        with(documents_started: documents_started + 1, doc_total: total, doc_done: 0,
          sections_total: sections_total + total)
      end

      # @param by [Integer] sections finished
      # @param failed [Integer] of those, sections that failed
      def advance(by: 1, failed: 0)
        done = doc_done + by
        finished_doc = doc_done < doc_total && done >= doc_total
        with(sections_done: sections_done + by, failures: failures + failed, doc_done: done,
          documents_done: documents_done + (finished_doc ? 1 : 0))
      end

      def item(name) = with(current_item: name&.to_s)

      # @param clauses [Integer] clauses a finished section wrote
      # @param defaulted [Integer] of those, clauses with placeholder annotations
      def note(clauses:, defaulted:) = with(clauses: self.clauses + clauses, defaulted: self.defaulted + defaulted)

      # @param backoff [Boolean] the line reports a 429 backoff
      def add_log(line, backoff: false)
        with(log: (log + [line]).last(State::LOG_LIMIT), backoffs: backoffs + (backoff ? 1 : 0))
      end

      def stop = with(stopping: true)
      def finish(status) = with(outcome: status.to_s)
      def tick(time) = with(now: time)

      # @return [Float] seconds since the run started
      def elapsed = [now - started_at, 0.0].max.to_f

      # @return [Float, nil] seconds per finished section
      def pace = sections_done.positive? ? elapsed / sections_done : nil

      # @return [Float] finished sections per minute
      def rate = elapsed.positive? ? sections_done * 60 / elapsed : 0.0

      # Sections the whole run is expected to have: the known total, scaled
      # up to the expected document count when only some documents started.
      def expected_sections
        return sections_total unless documents_total && documents_started.positive? && documents_total > documents_started

        (sections_total * documents_total.to_f / documents_started).ceil
      end

      # @return [Float, nil] seconds until the whole run is done
      def run_eta = pace && ([expected_sections - sections_done, 0].max * pace)

      # @return [Float, nil] seconds until the current document is done
      def document_eta = pace && ([doc_total - doc_done, 0].max * pace)
    end

    # Log lines kept for the events panel.
    State::LOG_LIMIT = 200
  end
end
