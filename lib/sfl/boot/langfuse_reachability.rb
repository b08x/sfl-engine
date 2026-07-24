# frozen_string_literal: true

require "socket"
require "uri"

module SFL
  module Boot
    # Pre-flight Langfuse/OpenTelemetry connectivity check, run by
    # SFL::Boot before LLM::Tracing.configure. Ported from legacy's
    # Compiler::LangfuseReachability
    # (sfl-compiler/lib/sfl/compiler/langfuse_reachability.rb) essentially
    # unchanged — the check itself (TCP-reachability probe, interactive
    # y/N prompt when a TTY is attached, auto-skip when not) has nothing
    # DSPy-specific about it.
    #
    # What IS dropped: legacy's file-top comment and its "must run before
    # `require 'ruby-spacy'`/`require 'dspy'`, standalone-loadable, NOT
    # autoloaded via Zeitwerk" constraints. Those existed only because
    # dspy-o11y-langfuse made a one-shot, require-time ENV read that had
    # to be pre-empted by unsetting ENV vars before that require ever
    # happened. LLM::Tracing.configure (this codebase's replacement) takes
    # host/public_key/secret_key as explicit arguments and is called
    # explicitly by Boot at call time, not triggered by any gem's require
    # — there is no one-shot decision to race here, so this class is a
    # perfectly ordinary Zeitwerk-autoloaded class like everything else
    # under lib/sfl/boot/.
    module LangfuseReachability
      # @param host_url [String]
      # @param timeout [Numeric] seconds
      # @return [Boolean]
      module_function def reachable?(host_url, timeout: 2)
        uri = URI.parse(host_url)
        port = uri.port || ((uri.scheme == "https") ? 443 : 80)
        Socket.tcp(uri.host, port, connect_timeout: timeout) { true }
      rescue
        false
      end

      # @param env [#[]] e.g. ENV
      # @param tty [Boolean] whether stdin is interactive
      # @param input [#gets] injectable for tests
      # @return [Symbol] :traced (no keys configured, or reachable),
      #   :skip_tracing (keys present but endpoint unreachable — continue
      #   without tracing), or :cancel (unreachable, interactive, user
      #   declined)
      module_function def decide(env:, tty:, input: $stdin)
        return :traced unless tracing_requested?(env)
        return :traced if reachable?(env["LANGFUSE_HOST"])

        explain_unreachable(env)
        return :skip_tracing unless tty

        prompt_to_continue(input)
      end

      module_function def tracing_requested?(env)
        env["LANGFUSE_PUBLIC_KEY"] && env["LANGFUSE_SECRET_KEY"] && env["LANGFUSE_HOST"]
      end

      module_function def explain_unreachable(env)
        warn "[WARN] Cannot reach Langfuse at #{env['LANGFUSE_HOST']} — " \
          "tracing would fail/spam errors throughout the run."
      end

      module_function def prompt_to_continue(input)
        warn "Continue without tracing? [y/N, N cancels the job] "
        (input.gets&.strip&.downcase == "y") ? :skip_tracing : :cancel
      end
    end
  end
end
