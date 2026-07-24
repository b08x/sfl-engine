# frozen_string_literal: true

module SFL
  module LLM
    # ruby_llm's structured-output response is a String-keyed Hash (JSON
    # parsed with default options); the rest of this codebase works in
    # symbol-keyed Hashes end-to-end. One shared conversion point for both
    # annotators rather than duplicating the recursive walk in each.
    module ResponseSymbolizer
      module_function def call(value)
        case value
        when Hash then value.to_h { |k, v| [k.to_sym, call(v)] }
        when Array then value.map { |v| call(v) }
        else value
        end
      end
    end
  end
end
