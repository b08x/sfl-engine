# frozen_string_literal: true

require "json"
require "open3"
require "securerandom"
require "timeout"

module SFL
  module Analysis
    # Client for sidecar/bertopic/bertopic_sidecar.py. Spawns the sidecar on
    # first use, checks the ready handshake, sends one NDJSON request per
    # #fit call, and restarts the process when the pipe breaks mid-request.
    #
    # The caller supplies the command and every setting. This class reads no
    # ENV; SFL::Boot is the only reader.
    # rubocop:disable-next Metrics/ClassLength -- one client: process lifecycle, protocol framing and result shaping
    class BertopicSidecar
      OUTLIER_TOPIC = -1
      MODEL = "bertopic"
      REQUEST_TYPE = "bertopic"
      READY_TYPE = "ready"
      MIN_TOPIC_SIZE_FLOOR = 2
      STARTUP_TIMEOUT_SECONDS = 60
      CLOSE_TIMEOUT_SECONDS = 5

      # Spawns the child with stdin/stdout pipes. Returns [stdin, stdout, wait_thread].
      DEFAULT_RUNNER = -> (command) { Open3.popen2(*command, pgroup: true) }

      # Pipe-level failure: the process died or its pipe broke. Retried by
      # #exchange and never escapes #fit.
      class TransportError < StandardError; end

      Handle = Struct.new(:stdin, :stdout, :wait_thread)

      # @param command [Array<String>] argv that starts the sidecar
      # @param logger [SFL::Core::Ports::Logger]
      # @param runner [#call] takes the command, returns [stdin, stdout, wait_thread]
      # @param max_restarts [Integer] restarts allowed per #fit call after a transport failure
      def initialize(command:, logger: SFL::Core::Ports::Null::Logger.new, runner: DEFAULT_RUNNER, max_restarts: 1)
        @command = command
        @logger = logger
        @runner = runner
        @max_restarts = max_restarts
        @mutex = Mutex.new
        @process = nil
      end

      # @param texts [Array<String>]
      # @param embeddings [Array<Array<Float>>] one vector per text, in order
      # @param seed [Integer]
      # @param k [Integer, nil] topic count; nil lets BERTopic choose
      # @param min_topic_size [Integer, nil] overrides the derived default
      # @return [Hash] :topics (Array<Integer>), :topic_words (Hash<Integer, Array<String>>), :coverage (Float)
      # rubocop:disable-next Naming/MethodParameterName -- k: is the keyword named in the sidecar contract
      def fit(texts:, embeddings:, seed:, k: nil, min_topic_size: nil)
        validate_inputs!(texts, embeddings, seed)
        payload = {
          type: REQUEST_TYPE,
          texts:,
          embeddings:,
          nr_topics: k,
          min_topic_size: min_topic_size || derive_min_topic_size(texts.size),
          seed:,
        }
        response = @mutex.synchronize { exchange(payload) }
        build_result(response, texts.size)
      end

      # Stops the sidecar. Safe to call more than once.
      # @return [nil]
      def close
        @mutex.synchronize { stop_process }
        nil
      end

      # Single place that sets the default minimum topic size from the corpus size.
      private def derive_min_topic_size(text_count) = [MIN_TOPIC_SIZE_FLOOR, text_count / 10].max

      private def validate_inputs!(texts, embeddings, seed)
        raise Error, "texts and embeddings must be Arrays" unless texts.is_a?(Array) && embeddings.is_a?(Array)
        raise Error, "texts and embeddings lengths differ: #{texts.size} != #{embeddings.size}" unless texts.size == embeddings.size
        raise Error, "at least 2 texts are required, got #{texts.size}" if texts.size < 2
        raise Error, "seed must be an Integer" unless seed.is_a?(Integer)
      end

      private def exchange(payload, restarts: 0)
        ensure_started
        send_request(payload)
      rescue TransportError => e
        if restarts >= @max_restarts
          @logger.error("bertopic sidecar transport failed permanently", command: command_line, restarts:, error_class: e.class, error_message: e.message)
          raise Error, "bertopic sidecar #{command_line} failed after #{restarts} restart(s): #{e.message}"
        end

        @logger.warn("bertopic sidecar transport failed, restarting", command: command_line, restarts:, max_restarts: @max_restarts, error_class: e.class, error_message: e.message)
        restart_process
        exchange(payload, restarts: restarts + 1)
      end

      private def send_request(payload)
        id = SecureRandom.uuid
        write_line(JSON.generate({ id: }.merge(payload)))
        response = parse_response(read_line)
        raise Error, response["error"] if response.key?("error")
        raise Error, "bertopic sidecar response id did not match the request" unless response["id"] == id

        response
      end

      private def parse_response(line)
        response = JSON.parse(line)
        raise Error, "bertopic sidecar response was not a JSON object" unless response.is_a?(Hash)

        response
      rescue JSON::ParserError => e
        raise Error, "bertopic sidecar response was not valid JSON: #{e.message}"
      end

      private def build_result(response, text_count)
        topics = response["topics"]
        raise Error, "bertopic sidecar response has no topics array" unless topics.is_a?(Array)
        raise Error, "bertopic sidecar returned #{topics.size} topics for #{text_count} texts" unless topics.size == text_count

        topic_words = (response["topic_words"] || {}).to_h { |id, words| [Integer(id, 10), words] }
        { topics:, topic_words:, coverage: coverage(topics) }
      end

      private def coverage(topics) = topics.count { |topic| topic != OUTLIER_TOPIC }.fdiv(topics.size)

      private def ensure_started
        start_process if @process.nil?
      end

      private def start_process
        @logger.debug("spawning bertopic sidecar", command: command_line)
        stdin, stdout, wait_thread = @runner.call(@command)
        @process = Handle.new(stdin, stdout, wait_thread)
        await_ready
        @logger.info("bertopic sidecar ready", command: command_line, pid: wait_thread.pid)
      rescue
        stop_process
        raise
      end

      private def await_ready
        line = Timeout.timeout(STARTUP_TIMEOUT_SECONDS) { @process.stdout.gets }
        raise Error, "bertopic sidecar exited before signaling ready" if line.nil?
        return if ready_line?(line)

        raise Error, "unexpected bertopic sidecar startup message: #{line.strip}"
      rescue Timeout::Error
        raise Error, "bertopic sidecar did not signal ready within #{STARTUP_TIMEOUT_SECONDS}s"
      end

      private def ready_line?(line)
        message = JSON.parse(line)
        message.is_a?(Hash) && message["type"] == READY_TYPE && message["model"] == MODEL
      rescue JSON::ParserError
        false
      end

      private def restart_process
        stop_process
        start_process
      end

      private def stop_process
        handle = @process
        @process = nil
        return if handle.nil?

        @logger.debug("stopping bertopic sidecar", command: command_line, pid: handle.wait_thread.pid)
        close_quietly(handle.stdin)
        close_quietly(handle.stdout)
        wait_for_exit(handle.wait_thread)
      end

      private def close_quietly(io)
        io.close
      rescue IOError
        nil
      end

      private def wait_for_exit(wait_thread)
        return if wait_thread.join(CLOSE_TIMEOUT_SECONDS)

        Process.kill("KILL", wait_thread.pid)
        wait_thread.join
      rescue Errno::ESRCH
        nil
      end

      private def write_line(line)
        @process.stdin.puts(line)
      rescue Errno::EPIPE, IOError => e
        raise TransportError, "failed writing to sidecar: #{e.message}"
      end

      private def read_line
        line = @process.stdout.gets
        raise TransportError, "sidecar closed the pipe" if line.nil?

        line
      rescue IOError => e
        raise TransportError, "failed reading from sidecar: #{e.message}"
      end

      private def command_line = @command.join(" ")
    end
  end
end
