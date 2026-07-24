# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Structured logging port, deliberately shaped like Ruby's stdlib
      # ::Logger (same five severities, same message-or-block calling
      # convention) so a concrete adapter can be a thin wrapper around a
      # real ::Logger instance rather than a bespoke protocol. Kept
      # separate from the Instrumenter port: Instrumenter wraps a call
      # with a named span for tracing/metrics (OTel/Langfuse), Logger
      # writes discrete human-readable lines — different consumers, different
      # backends, no reason to force them through one interface.
      #
      # Level guidance (apply this consistently across call sites, not
      # just here):
      #   debug — fine-grained, high-volume diagnostic detail (e.g. a
      #           per-request payload). Off by default in production;
      #           only for someone actively troubleshooting this component.
      #   info  — a normal operational milestone worth seeing by default
      #           (process started/completed, counts, latency). Not
      #           spammy: one line per unit of work, not per iteration.
      #   warn  — something degraded or self-healed without failing the
      #           caller (a retry succeeded, a fuzzy/fallback value was
      #           substituted, a subprocess crashed and was restarted).
      #           The operation still completed; a human should still know.
      #   error — an operation failed and could not complete as
      #           requested, though the process itself survives.
      #   fatal — unrecoverable: a critical dependency is permanently
      #           gone, or the process is about to exit.
      module Logger
        # @param message [String, nil]
        # @yield returns the message when no message argument is given
        def debug(message = nil, &)
          raise NotImplementedError, "#{self.class} must implement #debug"
        end

        # @param message [String, nil]
        # @yield returns the message when no message argument is given
        def info(message = nil, &)
          raise NotImplementedError, "#{self.class} must implement #info"
        end

        # @param message [String, nil]
        # @yield returns the message when no message argument is given
        def warn(message = nil, &)
          raise NotImplementedError, "#{self.class} must implement #warn"
        end

        # @param message [String, nil]
        # @yield returns the message when no message argument is given
        def error(message = nil, &)
          raise NotImplementedError, "#{self.class} must implement #error"
        end

        # @param message [String, nil]
        # @yield returns the message when no message argument is given
        def fatal(message = nil, &)
          raise NotImplementedError, "#{self.class} must implement #fatal"
        end
      end
    end
  end
end
