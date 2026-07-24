# frozen_string_literal: true

# Small, deliberately duck-typed builders for the Core::Types structs
# spec/analysis/* needs repeatedly (SyntacticToken -> AnnotatedClause ->
# ConversationTurn) — every analysis unit spec drives real dry-struct
# instances rather than doubles, so these factories exist purely to avoid
# re-typing the same nested literal in a dozen spec files. Kept minimal:
# only the attributes analysis code actually reads get a meaningful
# default, everything else is a a neutral filler value.
module AnalysisFactories
  # rubocop:disable Metrics/ParameterLists -- one flat SyntacticToken builder; every kwarg maps
  # 1:1 to a real SyntacticToken attribute a cohesion-analyzer spec needs to vary independently.
  def build_token(text: "word", lemma: text.downcase, pos: "NOUN", tag: "NN", dep: "ROOT", index: 0)
    SFL::Core::Types::SyntacticToken.new(
      text:, lemma:, pos:, tag:, dep:, head_index: -1, morphology: {}, index:
    )
  end
  # rubocop:enable Metrics/ParameterLists

  def build_syntactic_clause(id: "syn-1", text: "text", tokens: [], document_id: "doc-1", sentence_index: 0)
    SFL::Core::Types::SyntacticClause.new(
      id:, text:, tokens:, root_index: 0, sentence_index:, document_id:
    )
  end

  def build_ideational(clause_id: "syn-1", process_type: "material", participants: [])
    SFL::Core::Types::IdeationalPayload.new(
      clause_id:, process_type:, participants:, circumstances: [], raw_transitivity: {}
    )
  end

  def build_interpersonal(clause_id: "syn-1", mood: "declarative", tenor: 0.5, modality: 0.5,
    annotation_source: "llm"
  )
    SFL::Core::Types::InterpersonalPayload.new(
      clause_id:, mood:, modality_weight: modality, tenor:, speaker_attitude: nil, reasoning: nil,
      annotation_source:
    )
  end

  # rubocop:disable Metrics/ParameterLists -- one flat AnnotatedClause builder covering every
  # field a spec/analysis/* example needs to vary; splitting it would just relocate the kwargs.
  def build_annotated_clause(
    id: "clause-1", text: "text", tokens: [], process_type: "material", participants: [],
    mood: "declarative", tenor: 0.5, modality: 0.5, annotation_source: "llm", document_id: "doc-1",
    sentence_index: 0
  )
    syntactic = build_syntactic_clause(id: "#{id}-syn", text:, tokens:, document_id:, sentence_index:)
    SFL::Core::Types::AnnotatedClause.new(
      id:, text:, syntactic:,
      ideational: build_ideational(clause_id: syntactic.id, process_type:, participants:),
      interpersonal: build_interpersonal(clause_id: syntactic.id, mood:, tenor:, modality:, annotation_source:),
      textual: nil, document_id:, compiled_at: Time.now
    )
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists -- one flat ConversationTurn builder; same rationale
  # as build_annotated_clause above.
  def build_turn(
    turn_id: 1, speaker: "Alice", avg_tenor: 0.5, avg_modality: 0.5, dominant_mood: "declarative",
    clauses: [], process_types: {}, participants: [], tenor_shift: nil, semantic_coherence_score: nil,
    dominant_topic: nil, topic_distribution: nil, message_text: "text", timestamp: Time.now
  )
    SFL::Core::Types::ConversationTurn.new(
      turn_id:, speaker:, timestamp:, message_text:, clauses:, avg_tenor:, avg_modality:, dominant_mood:,
      process_types:, participants:, tenor_shift:, semantic_coherence_score:, dominant_topic:,
      topic_distribution:
    )
  end
  # rubocop:enable Metrics/ParameterLists
end

RSpec.configure do |config|
  config.include AnalysisFactories, file_path: %r{spec/analysis}
end
