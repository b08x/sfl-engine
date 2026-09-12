# frozen_string_literal: true

require "time"

module SFL
  module Core
    # JSON serialization boundary for SFL::Core::Types value objects.
    #
    # Dry::Struct#to_h is already recursive but leaves Time attributes as
    # Time objects, which don't survive a real JSON round trip (job queues,
    # HTTP responses, and file persistence all serialize through JSON, not
    # Ruby's Marshal). `dump` stringifies every Time to ISO8601; the
    # `load_*` methods reverse that for the specific attributes that are
    # typed as Time, then hand the rest to Dry::Struct's own Hash coercion.
    #
    # Deliberately separate from SFL::Core::Types (decision: Types defines
    # value objects, Wire defines how they cross a process boundary) so
    # neither file grows unrelated responsibilities.
    module Wire
      module_function def dump(struct)
        deep_stringify_time(struct.to_h)
      end

      module_function def deep_stringify_time(value)
        case value
        when ::Time then value.iso8601
        when Hash then value.transform_values { |v| deep_stringify_time(v) }
        when Array then value.map { |v| deep_stringify_time(v) }
        else value
        end
      end

      # Reconstructs an AnnotatedClause from a Hash produced by `dump` (after
      # a JSON.generate / JSON.parse(symbolize_names: true) round trip) —
      # only `compiled_at` and `interpersonal.reasoning_trace.generated_at`
      # need explicit Time parsing; every other nested struct has no
      # Time-typed attributes, so Dry::Struct's own Hash coercion handles
      # them.
      module_function def load_annotated_clause(hash)
        interp = hash[:interpersonal]
        merged_interp = if interp && interp[:reasoning_trace]
          rt = interp[:reasoning_trace]
          coerced_rt = rt.merge(generated_at: ::Time.parse(rt.fetch(:generated_at).to_s))
          interp.merge(reasoning_trace: coerced_rt)
        else
          interp
        end
        Types::AnnotatedClause.new(
          hash.merge(
            compiled_at: ::Time.parse(hash.fetch(:compiled_at)),
            interpersonal: merged_interp
          )
        )
      end
      # Reconstructs a ConversationTurn from a Hash produced by `dump`.
      module_function def load_conversation_turn(hash)
        Types::ConversationTurn.new(
          hash.merge(
            timestamp: ::Time.parse(hash.fetch(:timestamp)),
            clauses: hash.fetch(:clauses).map { |c| load_annotated_clause(c) }
          )
        )
      end

      module_function def load_speaker_profile(hash)
        Types::SpeakerProfile.new(hash)
      end

      module_function def load_key_moment(hash)
        Types::KeyMoment.new(hash)
      end

      module_function def load_example_passage(hash)
        Types::ExamplePassage.new(hash)
      end

      # Reconstructs an AnalysisResult from a Hash produced by `dump`.
      module_function def load_analysis_result(hash)
        Types::AnalysisResult.new(
          hash.merge(
            turns: hash.fetch(:turns).map { |t| load_conversation_turn(t) },
            speaker_profiles: hash.fetch(:speaker_profiles).to_h { |k, p| [k.to_s, load_speaker_profile(p)] },
            key_moments: hash.fetch(:key_moments, []).map { |m| load_key_moment(m) },
            example_passages: hash.fetch(:example_passages, []).map { |p| load_example_passage(p) }
          )
        )
      end
    end
  end
end
