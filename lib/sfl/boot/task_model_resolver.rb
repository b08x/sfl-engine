# frozen_string_literal: true

module SFL
  module Boot
    # Resolves each task's provider and model in the order: the
    # SFL_TASK_<TASK>_MODEL env var, then the task's `task_models` row, then
    # the built-in default. Boot builds it with the env hash, so this class
    # reads no ENV itself; the store is absent when the database is not
    # required, and then only env and defaults apply.
    class TaskModelResolver
      # The capability a task's model needs; tasks not listed need "chat".
      CAPABILITY_BY_TASK = { embedding: "embedding" }.freeze
      DEFAULT_CAPABILITY = "chat"

      # Model for every LLM task with no env var, no task_models row and no
      # derived default. A free OpenRouter model (zero prompt and completion
      # pricing), so no call defaults to a paid model.
      DEFAULT_LLM_MODEL = "google/gemma-4-26b-a4b-it:free"

      # Tasks whose default is another task's effective model, resolved
      # after that task. The rest default to DEFAULT_PROVIDER and
      # DEFAULT_LLM_MODEL (or the embedding default for :embedding).
      DERIVED_DEFAULTS = {
        context_synthesis: :pass_two_annotation,
        narrative_generation: :context_synthesis,
        ingest_classification: :embedding,
        loader_drafting: :pass_two_annotation,
      }.freeze

      # One task's effective model.
      # - `source`: :env, :db or :default
      # - `env_var`: the variable that set the model when source is :env
      # - `model`: nil when nothing configures the task
      Resolution = Data.define(:task, :provider, :model, :source, :env_var, :params) do
        def to_task_config = LLM::TaskConfig.new(model:, provider:, params:, source:, env_var:)
      end

      # @param task [Symbol]
      # @return [String] the capability the task's model must list
      def self.capability(task) = CAPABILITY_BY_TASK.fetch(task.to_sym, DEFAULT_CAPABILITY)

      # @param env [#[]] environment values
      # @param store [Core::Ports::ModelStore, nil] the `task_models` assignments
      def initialize(env:, store: nil)
        @env = env
        @store = store
      end

      # @return [Hash{Symbol => Resolution}] every Boot::TASK_NAMES task, in that order
      # @raise [Boot::Error] when the store's assignments cannot be read
      def resolve
        assignments = read_assignments
        TASK_NAMES.each_with_object({}) do |task, resolved|
          resolved[task] = resolve_task(task, assignments[task], default_for(task, resolved))
        end
      end

      # @return [LLM::Config] each task's TaskConfig, carrying its source
      def call = LLM::Config.new(tasks: resolve.transform_values(&:to_task_config))

      private def read_assignments
        return {} unless @store

        @store.assignments
      rescue => e
        raise Error, "cannot read task_models (run rake db:migrate?): #{e.class}: #{e.message}"
      end

      private def default_for(task, resolved)
        base = DERIVED_DEFAULTS[task]
        return [resolved.fetch(base).provider, resolved.fetch(base).model] if base
        return [DEFAULT_EMBEDDING_PROVIDER, Store::PgEmbeddingStore::DEFAULT_MODEL] if task == :embedding

        [DEFAULT_PROVIDER, DEFAULT_LLM_MODEL]
      end

      private def resolve_task(task, assignment, (default_provider, default_model))
        prefix = "SFL_TASK_#{task.to_s.upcase}_"
        params = Boot.task_params_from_env(prefix, @env)
        env_provider = Boot.presence(@env["#{prefix}PROVIDER"])&.to_sym
        env_var = model_var(prefix)
        if env_var
          return Resolution.new(task:, provider: env_provider || default_provider, model: @env[env_var], source: :env,
            env_var:, params:)
        end
        if assignment
          return Resolution.new(task:, provider: assignment[:provider].to_sym, model: assignment[:model_id], source: :db,
            env_var: nil, params:)
        end

        Resolution.new(task:, provider: env_provider || default_provider, model: default_model, source: :default,
          env_var: nil, params:)
      end

      private def model_var(prefix)
        name = "#{prefix}MODEL"
        name if Boot.presence(@env[name])
      end
    end
  end
end
