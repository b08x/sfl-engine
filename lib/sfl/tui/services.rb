# frozen_string_literal: true

require "dry/monads"
require "securerandom"

module SFL
  module TUI
    # The collaborators commands close over. App.build fills it from Boot;
    # specs fill it with fakes.
    #
    # - `source`: Core::Ports::BrowseSource
    # - `review_queue`: #decide(id:, decision:, reviewer:), Store::PgReviewQueueRepository
    # - `recompiler`: (text, section_id:) -> Dry::Monads::Result, Pipeline#compile with store and embed on
    # - `editor`: Core::Ports::Editor
    # - `opener`: Core::Ports::Opener
    # - `run_log`: Core::Ports::RunLog
    # - `retriever`: Core::Ports::Retriever
    # - `exporter`: #call(picks, format) -> `{path:, count:}`, Export::Exporter
    # - `reviewer`: String, nil when SFL_REVIEWER_NAME is unset
    # - `run_id`: #call -> a new run id
    # - `model_store`: Core::Ports::ModelStore, the `models` and `task_models` tables
    # - `model_resolver`: Boot::TaskModelResolver, #resolve -> task => Resolution
    # - `model_refresher`: LLM::ModelRefresher, #call -> Array<Outcome>
    # - `run_models`: Hash, nil without LLM settings; the run header's models
    #   (LLM::Config#header) recorded on recompile runs
    # - `terminal_host`: Core::Ports::TerminalHost, kitty or null
    # - `spawner`: #call(argv, env:, name:) -> log path, Launcher::DetachedChild
    Services = Data.define(:source, :review_queue, :recompiler, :editor, :opener, :run_log, :retriever, :exporter,
      :reviewer, :logger, :run_id, :model_store, :model_resolver, :model_refresher, :run_models, :terminal_host,
      :spawner) do
      # @return [Services] every collaborator a null adapter, for specs to override
      def self.null(**overrides)
        source = overrides.fetch(:source, Core::Ports::Null::BrowseSource.new)
        run_log = overrides.fetch(:run_log, Core::Ports::Null::RunLog.new)
        model_store = overrides.fetch(:model_store, Core::Ports::Null::ModelStore.new)
        new(
          source:,
          review_queue: nil,
          recompiler: -> (_text, section_id:) { Dry::Monads::Success(section_id) },
          editor: Core::Ports::Null::Editor.new,
          opener: Core::Ports::Null::Opener.new,
          run_log:,
          retriever: Core::Ports::Null::Retriever.new,
          exporter: nil,
          reviewer: nil,
          logger: Core::Ports::Null::Logger.new,
          run_id: -> { SecureRandom.uuid },
          model_store:,
          model_resolver: Boot::TaskModelResolver.new(env: {}, store: model_store),
          model_refresher: LLM::ModelRefresher.new(catalogs: [], store: model_store, logger: Core::Ports::Null::Logger.new),
          run_models: nil,
          terminal_host: Core::Ports::Null::TerminalHost.new,
          spawner: -> (_argv, **) { File::NULL },
          **overrides.except(:source, :run_log, :model_store)
        )
      end
    end
  end
end
