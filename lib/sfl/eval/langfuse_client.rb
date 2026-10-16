# frozen_string_literal: true

require "base64"
require "json"
require "socket"
require "timeout"
require "uri"

module SFL
  module Eval
    # Minimal Langfuse public-API client for the evaluation harness: datasets,
    # items, score configs, annotation queues, scores, and dataset run items.
    #
    # Configuration arrives by constructor (SFL::Boot is the sole ENV reader).
    # The transport is any callable (method, url, headers, body) -> Response, so
    # specs run without a network and the default uses Net::HTTP.
    class LangfuseClient
      Response = Struct.new(:status, :body)

      class Error < StandardError
        attr_reader :status

        def initialize(message, status: nil)
          super(message)
          @status = status
        end
      end

      PAGE_LIMIT = 50

      def initialize(host:, public_key:, secret_key:, transport: NetHttpTransport.new,
        logger: Core::Ports::Null::Logger.new
      )
        @host = host.to_s.chomp("/")
        @auth = "Basic #{Base64.strict_encode64("#{public_key}:#{secret_key}")}"
        @transport = transport
        @logger = logger
      end

      def list_datasets
        paged("/api/public/v2/datasets")
      end

      def upsert_dataset(name:, description: nil, metadata: nil)
        post("/api/public/v2/datasets", compact(name:, description:, metadata:))
      end

      # POST /dataset-items upserts by id, so reruns overwrite instead of duplicating.
      def upsert_dataset_item(dataset:, id:, input:, expected_output: nil, metadata: nil)
        post("/api/public/dataset-items",
          compact(datasetName: dataset, id:, input:, expectedOutput: expected_output, metadata:))
      end

      def list_dataset_items(dataset:)
        paged("/api/public/dataset-items", "datasetName=#{URI.encode_www_form_component(dataset)}")
      end

      def list_score_configs
        paged("/api/public/score-configs")
      end

      def ensure_score_config(name:, data_type:, categories: nil, min_value: nil, max_value: nil, description: nil)
        existing = list_score_configs.find { |config| config["name"] == name }
        return existing if existing

        post("/api/public/score-configs",
          compact(name:, dataType: data_type, categories:, minValue: min_value, maxValue: max_value,
            description:))
      end

      def list_annotation_queues
        paged("/api/public/annotation-queues")
      end

      def create_annotation_queue(name:, description: nil, score_config_ids: [])
        post("/api/public/annotation-queues",
          compact(name:, description:, scoreConfigIds: score_config_ids))
      end

      # @param fields [Hash] Langfuse score body keys (traceId, datasetRunId, comment, dataType, configId, id, ...)
      def create_score(name:, value:, **fields)
        post("/api/public/scores", compact({ name:, value: }.merge(fields)))
      end

      def create_run_item(run_name:, dataset_item_id:, trace_id: nil, observation_id: nil, metadata: nil)
        post("/api/public/dataset-run-items",
          compact(runName: run_name, datasetItemId: dataset_item_id, traceId: trace_id,
            observationId: observation_id, metadata:))
      end

      private def get(path)
        request(:get, path)
      end

      private def post(path, body)
        request(:post, path, body)
      end

      private def paged(path, query = nil)
        results = []
        page = 1
        loop do
          reply = get("#{path}?#{[query, "page=#{page}", "limit=#{PAGE_LIMIT}"].compact.join('&')}")
          results.concat(reply["data"] || [])
          break if page >= (reply.dig("meta", "totalPages") || 0)

          page += 1
        end
        results
      end

      # Logs method, path, status and latency only. Headers, keys and bodies
      # (request or response) never reach the logger.
      private def request(method, path, body = nil)
        headers = { "Authorization" => @auth, "Content-Type" => "application/json" }
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = @transport.call(method, "#{@host}#{path}", headers, body && JSON.generate(body))
        log_response(method, path, response.status, started_at)
        unless (200..299).cover?(response.status)
          raise Error.new("Langfuse #{method.upcase} #{path} failed: #{response.status} #{response.body}",
            status: response.status)
        end

        response.body.to_s.empty? ? {} : JSON.parse(response.body)
      rescue SystemCallError, SocketError, IOError, Timeout::Error => e
        @logger.error("langfuse request failed", method: method.to_s.upcase, path:, error_class: e.class,
          latency_ms: elapsed_ms(started_at))
        raise Error, "Langfuse unreachable at #{@host}: #{e.class}: #{e.message}"
      end

      private def log_response(method, path, status, started_at)
        fields = { method: method.to_s.upcase, path:, status:, latency_ms: elapsed_ms(started_at) }
        if (200..299).cover?(status)
          @logger.debug("langfuse request", **fields)
        else
          @logger.warn("langfuse request returned non-2xx", **fields)
        end
      end

      private def elapsed_ms(started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      end

      private def compact(hash)
        hash.compact
      end
    end
  end
end
