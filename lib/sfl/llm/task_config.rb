# frozen_string_literal: true

require "dry-struct"

module SFL
  module LLM
    # One task's {provider, model, params} resolution (track decision 8).
    # `provider` is optional because RubyLLM can auto-detect it from the
    # model id; `params` holds chat-level knobs (e.g. temperature) applied
    # by ChatFactory, never read by name anywhere else.
    class TaskConfig < ::Dry::Struct
      attribute :model, Core::Types::String
      attribute :provider, Core::Types::Symbol.optional.default(nil)
      attribute :params, Core::Types::Hash.default({}.freeze)
    end
  end
end
