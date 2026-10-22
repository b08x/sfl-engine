# frozen_string_literal: true

require "dry/monads"

module SFL
  module TUI
    module Launcher
      # Starts a launcher Request (decision 14): in a new terminal tab when
      # the TerminalHost can open one, else as a detached child whose run
      # the Runs tab shows. The child records its run under the SFL_RUN_ID
      # given here, so both paths are one run in the `runs` table.
      module Commands
        extend self

        # @return [Proc] -> Messages::Launched
        def start(services, request)
          SafeCommand.wrap(source: :launcher, logger: services.logger) do
            next Dry::Monads::Failure("no such path: #{request.path}") unless File.exist?(request.path)

            run_id = services.run_id.call
            env = { "SFL_RUN_ID" => run_id }
            next tab_message(request, run_id) if in_tab?(services, request, env)

            log = services.spawner.call(request.argv, env:, name: "ingest-#{run_id}")
            services.logger.info("ingest started", run_id:, collection: request.collection, path: request.path, log:)
            Messages::Launched.new(text: "ingest #{request.collection} started as run #{run_id}, log #{log}", detached: true)
          end
        end

        private def tab_message(request, run_id)
          Messages::Launched.new(text: "ingest #{request.collection} started in a new tab as run #{run_id}", detached: false)
        end

        # A host that fails is treated like one that cannot open tabs.
        private def in_tab?(services, request, env)
          services.terminal_host.launch_tab(cmd: request.argv, cwd: ROOT, title: "sfl ingest #{request.collection}", env:)
        rescue Core::Ports::TerminalHost::Error => e
          services.logger.warn("terminal tab failed, starting a detached ingest", error: e.message)
          false
        end
      end
    end
  end
end
