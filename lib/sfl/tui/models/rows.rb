# frozen_string_literal: true

module SFL
  module TUI
    module Models
      # View model for the Models tab: task rows from the resolver's
      # resolutions, the models a task may use, and the table cells. Pure.
      module Rows
        extend self

        TASK_HEADER = %w[task provider model source note].freeze
        MODEL_HEADER = %w[provider model context status].freeze
        WARNING = "! unavailable"

        # @param resolutions [Hash{Symbol => Boot::TaskModelResolver::Resolution}]
        # @param models [Array<Hash>] ModelStore#list rows
        # @return [Array<Hash>] task, provider, model, source, env_var, capability, unavailable
        def tasks(resolutions, models)
          unavailable = models.reject { |row| row[:available] }.to_set { |row| [row[:provider], row[:model_id]] }
          resolutions.values.map do |resolution|
            {
              task: resolution.task,
              provider: resolution.provider&.to_s,
              model: resolution.model,
              source: resolution.source,
              env_var: resolution.env_var,
              capability: Boot::TaskModelResolver.capability(resolution.task),
              unavailable: unavailable.include?([resolution.provider&.to_s, resolution.model]),
            }
          end
        end

        # @return [Array<Hash>] the models listing +capability+
        def candidates(models, capability) = models.select { |row| Array(row[:capabilities]).include?(capability) }

        def locked?(task) = task[:source] == :env

        # @return [Array<String>]
        def task_cell(task)
          [task[:task].to_s, task[:provider].to_s, task[:model] || "-", task[:source].to_s, note(task)]
        end

        # @return [Array<String>]
        def model_cell(model)
          [model[:provider], model[:model_id], model[:context_window]&.to_s || "-", model[:available] ? "" : "unavailable"]
        end

        private def note(task)
          notes = []
          notes << "locked #{task[:env_var]}" if locked?(task)
          notes << WARNING if task[:unavailable]
          notes.join(" ")
        end
      end
    end
  end
end
