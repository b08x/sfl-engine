# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for evidence-grounded query synthesis —
      # replaces DSPy::Signature's SynthesisSignature output block (track
      # decision 7), the same way ClauseAnnotationSchema replaces
      # SFLSignature for Pass 2. `cited_clause_numbers` is an array of
      # plain integers (evidence numbers, 1-indexed into the numbered
      # evidence block ContextSynthesizer builds) — verified against the
      # installed ruby_llm-schema 0.4.0 gem source
      # (lib/ruby_llm/schema/dsl/schema_builders.rb#determine_array_items):
      # `array :name, of: :integer` sends `:integer` to `#{of}_schema`
      # (`integer_schema`) when `of` is a primitive type symbol and no
      # block is given, so this is the correct form for an array of plain
      # scalars — the `array :x do object do ... end end` block form
      # ClauseAnnotationSchema's `premises` field uses is only for arrays
      # of objects.
      class SynthesisSchema < RubyLLM::Schema
        string :answer, description: "Answer grounded in the evidence"
        array :cited_clause_numbers, of: :integer,
          description: "Evidence numbers actually used (subset of the input numbering)"
        number :confidence, description: "0.0-1.0, lower when evidence is thin or conflicting",
          minimum: 0.0, maximum: 1.0
      end
    end
  end
end
