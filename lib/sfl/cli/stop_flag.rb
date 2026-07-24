# frozen_string_literal: true

module SFL
  module CLI
    # Cooperative stop signal for the two-stage Ctrl+C UX: a SIGINT trap
    # (installed by CLI.install_interrupt_trap) calls #stop!, and
    # Analysis::Engine/Analysis::KnowledgeBaseSource poll #stopped? once
    # per turn/artifact, finishing whatever unit is already in flight
    # before breaking out. Plain boolean read/write needs no Mutex —
    # exactly one writer (the trap) and one reader (the compile loop),
    # never concurrently. Ported near-verbatim from legacy's
    # Compiler::StopFlag.
    class StopFlag
      def initialize
        @stopped = false
      end

      def stop!
        @stopped = true
      end

      def stopped?
        @stopped
      end
    end
  end
end
