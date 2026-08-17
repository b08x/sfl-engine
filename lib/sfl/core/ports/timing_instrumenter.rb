# frozen_string_literal: true

require "json"

module SFL
  module Core
    module Ports
      # In-process Pass 2 timing collector. It records monotonic spans and
      # exposes a JSON-safe report without changing the instrumented result.
      class TimingInstrumenter
        include Ports::Instrumenter

        def initialize(clock: Process)
          @clock = clock
          @spans = []
          @mutex = Mutex.new
        end

        # @param name [String] span name
        # @param payload [Hash] span dimensions
        # @return [Object] the block result
        def instrument(name, payload = {})
          started_at = monotonic
          result = yield
          result
        ensure
          elapsed_ms = ((monotonic - started_at) * 1000).round(3)
          @mutex.synchronize { @spans << { name:, duration_ms: elapsed_ms, **payload } }
        end

        # @return [Hash] structured timing breakdown
        def report
          spans = @mutex.synchronize { @spans.dup }
          provider = spans.select { |span| span[:name] == "pass_two.provider_request" }
          retries = spans.select { |span| span[:name] == "pass_two.retry" }
          parsing = spans.select { |span| span[:name].start_with?("pass_two.parse.") }
          clauses = spans.select { |span| span[:name] == "pass_two.clause" }
          batches = spans.select { |span| span[:name] == "pass_two.batch" }

          batch_report = batches.map do |batch|
            batch.merge(idle_ms: [batch[:duration_ms] - provider.sum { |s| s[:duration_ms] } - parsing.sum { |s| s[:duration_ms] }, 0].max)
          end

          {
            clauses: clauses,
            batches: batch_report,
            provider_requests: provider,
            retries: { attempts: retries.length, duration_ms: retries.sum { |s| s[:duration_ms] }, spans: retries },
            parsing: parsing,
            totals_ms: {
              clause: clauses.sum { |s| s[:duration_ms] },
              batch: batches.sum { |s| s[:duration_ms] },
              provider: provider.sum { |s| s[:duration_ms] },
              parsing: parsing.sum { |s| s[:duration_ms] },
            },
          }
        end

        # @return [String] compact JSON report suitable for structured logs
        def report_json
          JSON.generate(report)
        end

        private

        attr_reader :clock

        def monotonic
          clock.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end

