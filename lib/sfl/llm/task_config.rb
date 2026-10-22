# frozen_string_literal: true

require "dry-struct"

module SFL
  module LLM
    # One task's {provider, model, params} resolution (track decision 8).
    # `provider` is optional because RubyLLM can auto-detect it from the
    # model id; `params` holds chat-level knobs (e.g. temperature) applied
    # by ChatFactory, never read by name anywhere else. `source` says where
    # the model came from (:env, :db or :default, Boot::TaskModelResolver)
    # and `env_var` names the variable when it came from env.
    class TaskConfig < ::Dry::Struct
      SOURCES = %i[env db default].freeze

      attribute :model, Core::Types::String
      attribute :provider, Core::Types::Symbol.optional.default(nil)
      attribute :params, Core::Types::Hash.default({}.freeze)
      attribute :source, Core::Types::Symbol.default(:default).enum(*SOURCES)
      attribute :env_var, Core::Types::String.optional.default(nil)
    end
  end
end
