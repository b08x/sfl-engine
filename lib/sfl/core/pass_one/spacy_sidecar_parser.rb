# frozen_string_literal: true

require "open3"
require "json"
require "securerandom"
require "timeout"

module SFL
  module Core
    module PassOne
      # SyntacticParser port adapter that talks to sidecar/spacy_sidecar.py
      # over NDJSON on stdin/stdout (track decision 2: Pass 1 never shares
      # the Ruby process). `command` defaults to a local `python3`
      # invocation but accepts anything that speaks the same protocol —
      # e.g. `["docker", "run", "-i", "--rm", "sfl-spacy-sidecar"]` — since
      # the transport is "a subprocess with stdin/stdout pipes," not
      # specifically Python-on-this-host.
      class SpacySidecarParser
        include Ports::SyntacticParser

        DEFAULT_SCRIPT_PATH = File.expand_path("../../../../sidecar/spacy_sidecar.py", __dir__)
        STARTUP_TIMEOUT_SECONDS = 30

        # @param env [Hash] extra subprocess environment (e.g. PYTHONPATH for a
        #   vendored interpreter whose packages live outside its own
        #   site-packages — see Boot::Result#pass1_env) merged over the
        #   current process's own env, not replacing it.
        def initialize(model:, command: nil, env: {}, logger: Ports::Null::Logger.new)
          @model = model
          @command = command || ["python3", DEFAULT_SCRIPT_PATH, "--model", model]
          @env = env
          @logger = logger
          @mutex = Mutex.new
          start_process
        end

        # @param text [String]
        # @param document_id [String, nil]
        # @return [Array<SFL::Core::Types::SyntacticClause>]
        def parse(text, document_id: nil)
          @mutex.synchronize { request(text, document_id) }
        end

        # @return [void]
        def close
          @mutex.synchronize do
            logger.debug { "closing sidecar (pid=#{wait_thread&.pid})" }
            stop_process
          end
        end

        attr_reader :stdin, :stdout, :wait_thread, :logger
        private :stdin, :stdout, :wait_thread, :logger

        private def start_process
          logger.debug { "spawning sidecar: #{@command.join(' ')}" }
          # pgroup: true puts the sidecar in its own process group so a
          # terminal Ctrl+C (SIGINT to the foreground process group) hits
          # only the Ruby process, not this child. CLI.install_interrupt_trap
          # relies on that isolation to finish the in-flight turn (which
          # needs a live sidecar) before shutting down cleanly.
          @stdin, @stdout, @wait_thread = Open3.popen2(@env, *@command, pgroup: true)
          await_ready
          logger.info { "sidecar ready (model=#{@model}, pid=#{wait_thread.pid})" }
        end

        private def await_ready
          line = Timeout.timeout(STARTUP_TIMEOUT_SECONDS) { stdout.gets }
          raise SidecarError, "sidecar exited before signaling ready" if line.nil?

          ready = JSON.parse(line)
          return if ready["type"] == "ready"

          raise SidecarError, "unexpected startup message: #{line.inspect}"
        rescue Timeout::Error
          raise SidecarError, "sidecar did not signal ready within #{STARTUP_TIMEOUT_SECONDS}s"
        end

        # A single crash-and-retry: transport failures restart the
        # subprocess exactly once and replay the request, so one dead
        # sidecar doesn't permanently wedge the parser, but a
        # persistently broken sidecar still surfaces as an error instead
        # of looping forever.
        private def request(text, document_id, retried: false)
          write_line(id: SecureRandom.uuid, text:, document_id:)
          response = read_response
          raise SidecarError, response["error"] if response["error"]

          build_clauses(response.fetch("clauses"))
        rescue Errno::EPIPE, IOError, SidecarError => e
          fail_or_retry(text, document_id, e, retried:)
        end

        private def fail_or_retry(text, document_id, error, retried:)
          if retried
            logger.error { "sidecar transport failed permanently: #{error.message}" }
            raise SidecarError, "sidecar transport failed: #{error.message}"
          end

          logger.warn { "sidecar transport failed (#{error.message}), restarting and retrying once" }
          restart_process
          request(text, document_id, retried: true)
        end

        private def read_response
          line = stdout.gets
          raise SidecarError, "sidecar closed the pipe" if line.nil?

          JSON.parse(line)
        end

        private def write_line(payload)
          stdin.puts(JSON.generate(payload))
        rescue Errno::EPIPE, IOError => e
          raise SidecarError, "failed writing to sidecar: #{e.message}"
        end

        private def restart_process
          stop_process
          start_process
        end

        private def stop_process
          stdin&.close
          stdout&.close
          wait_thread&.value
        rescue IOError
          nil
        end

        private def build_clauses(clause_hashes)
          clause_hashes.map { |clause_hash| build_clause(clause_hash) }
        end

        private def build_clause(clause_hash)
          Types::SyntacticClause.new(
            id: clause_hash.fetch("id"),
            text: clause_hash.fetch("text"),
            tokens: clause_hash.fetch("tokens").map { |token_hash| build_token(token_hash) },
            root_index: clause_hash.fetch("root_index"),
            sentence_index: clause_hash.fetch("sentence_index"),
            document_id: clause_hash["document_id"]
          )
        end

        private def build_token(token_hash)
          Types::SyntacticToken.new(
            text: token_hash.fetch("text"),
            lemma: token_hash.fetch("lemma"),
            pos: token_hash.fetch("pos"),
            tag: token_hash.fetch("tag"),
            dep: token_hash.fetch("dep"),
            head_index: token_hash.fetch("head_index"),
            morphology: token_hash.fetch("morphology"),
            index: token_hash.fetch("index")
          )
        end
      end
    end
  end
end
