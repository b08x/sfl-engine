# frozen_string_literal: true

# Test doubles for the JSON records steps: a capturing logger and a registry that
# keeps unit text only when a transaction commits.
module JsonRecordsSteps
  class Failed < StandardError; end

  # Keeps every warn and error call, with the same shape the SillyTavern steps read.
  class CaptureLogger
    attr_reader :warnings, :errors

    def initialize
      @warnings = []
      @errors = []
    end

    def warn(message = nil, **fields, &block) = @warnings << { message: message || block&.call, fields: }
    def error(message = nil, **fields, &block) = @errors << { message: message || block&.call, fields: }
    def debug(*, **) = nil
    def info(*, **) = nil
    def fatal(*, **) = nil
  end

  # Wraps a section registry and records each unit's text under its section id.
  # The text is kept only when the transaction commits, which is what a stored
  # row holds. Section rows have no text column, so this stands in for one.
  class LedgerRegistry
    def initialize(inner, ledger)
      @inner = inner
      @ledger = ledger
      @pending = nil
    end

    def transaction
      pending = {}
      result = @inner.transaction do
        @pending = pending
        yield
      end
      @ledger.merge!(pending)
      result
    end

    def register(unit, clause_count)
      @inner.register(unit, clause_count)
      @pending[unit.section_id] = unit.text
    end

    def written = @inner.written

    def reconcile(written) = @inner.reconcile(written)
  end
end
