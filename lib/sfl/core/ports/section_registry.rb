# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Records which collection, document and section each stored unit
      # belongs to. Pipeline calls #register after ClauseStore#replace_section,
      # inside #transaction, so the clause, document and section writes commit
      # together.
      #
      # Rules an adapter implements: the first unit of a document seen by this
      # registry moves an existing document from another collection (logging a
      # warning naming both) and replaces the document's earlier sections. A
      # section id already stored under a different document is never moved:
      # #register logs a warning and raises ConflictError, and writes nothing.
      module SectionRegistry
        # Raised when a unit's section id is stored under a different
        # document_key. Ingest reports it per file.
        class ConflictError < SFL::Error; end

        # @yield the writes that must commit together
        # @return [Object] the block's value
        def transaction
          raise NotImplementedError, "#{self.class} must implement #transaction"
        end

        # @param unit [SFL::Core::Types::Unit]
        # @param clause_count [Integer]
        # @return [void]
        def register(unit, clause_count)
          raise NotImplementedError, "#{self.class} must implement #register"
        end
      end
    end
  end
end
