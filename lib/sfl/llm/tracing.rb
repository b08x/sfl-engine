# frozen_string_literal: true

require "base64"
require "opentelemetry-sdk"
require "opentelemetry-exporter-otlp"
require "opentelemetry-instrumentation-ruby_llm"

module SFL
  module LLM
    # Wires ruby_llm chat spans into Langfuse via its OTel-compatible OTLP
    # endpoint (track decision 7's tracing-continuity requirement),
    # replacing dspy-o11y-langfuse's require-time, ENV-reading, one-shot
    # configuration (see legacy lib/sfl/compiler/bootstrap.rb). This class
    # takes host/public_key/secret_key as arguments rather than reading
    # ENV itself — the composition root (Boot, Phase 4) is what will read
    # those from ENV and call .configure (decision 4: ENV read only at
    # Boot). sdk:/exporter_class:/span_processor_class: are injectable so
    # specs never touch the real global OpenTelemetry TracerProvider.
    #
    # OpenTelemetry::SDK.configure may only run once per process (a second
    # call raises) — .configure is a no-op returning false after the
    # first successful call, mirroring the guard legacy Bootstrap needed
    # around dspy-o11y-langfuse's own one-shot configuration.
    class Tracing
      # https://langfuse.com/docs/opentelemetry: POST {host}/api/public/otel/v1/traces,
      # Basic-authenticated with public_key:secret_key. The /v1/traces suffix is the
      # OTLP/HTTP signal-specific path required by the spec — the exporter does NOT
      # append it automatically when an explicit endpoint: is passed (only its nil/env
      # fallback path does), so it must be included here.
      OTLP_PATH = "/api/public/otel/v1/traces"

      class << self
        # rubocop:disable Naming/PredicateMethod -- named to mirror OpenTelemetry::SDK.configure,
        # which this wraps; the boolean return is "did this call perform configuration," a
        # side detail for the idempotency guard, not the method's primary purpose.
        # rubocop:disable Metrics/ParameterLists -- three required config values plus three
        # injectable seams (sdk/exporter_class/span_processor_class) so specs never touch the
        # real global OpenTelemetry TracerProvider.
        # @return [Boolean] true if this call performed configuration, false if already configured
        def configure(
          host:,
          public_key:,
          secret_key:,
          sdk: ::OpenTelemetry::SDK,
          exporter_class: ::OpenTelemetry::Exporter::OTLP::Exporter,
          span_processor_class: ::OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor
        )
          return false if configured?

          exporter = exporter_class.new(endpoint: "#{host}#{OTLP_PATH}", headers: auth_headers(public_key, secret_key))
          sdk.configure do |c|
            c.use "OpenTelemetry::Instrumentation::RubyLLM"
            c.add_span_processor(span_processor_class.new(exporter))
          end

          @configured = true # rubocop:disable ThreadSafety/ClassInstanceVariable -- set once per process, before any traced call runs
          true
        end
        # rubocop:enable Naming/PredicateMethod, Metrics/ParameterLists

        def configured?
          @configured == true # rubocop:disable ThreadSafety/ClassInstanceVariable -- see #configure
        end

        private def auth_headers(public_key, secret_key)
          { "Authorization" => "Basic #{Base64.strict_encode64("#{public_key}:#{secret_key}")}" }
        end
      end
    end
  end
end
