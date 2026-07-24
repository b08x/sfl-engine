# frozen_string_literal: true

require "dry-struct"

module SFL
  module LLM
    # Per-task model/provider configuration (track decision 8): a map of
    # task name (e.g. :pass_two_annotation, :pass_two_batch_annotation,
    # :embedding) to its own TaskConfig, so different pipeline stages can
    # use different providers/models/cost-quality tradeoffs. Built once by
    # the composition root from ENV/a config file and injected — this
    # class itself never reads ENV.
    class Config < ::Dry::Struct
      attribute :tasks, Core::Types::Hash.map(Core::Types::Symbol, TaskConfig)

      # @param task [Symbol]
      # @return [TaskConfig]
      # @raise [SFL::LLM::Error] if no TaskConfig is registered for task
      def for(task)
        tasks.fetch(task) { raise Error, "no model/provider configured for task #{task.inspect}" }
      end
    end
  end
end
