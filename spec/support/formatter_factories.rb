# frozen_string_literal: true

# Small, deliberately duck-typed builders for the Core::Types structs
# spec/formatters/* needs repeatedly (KnowledgeArtifact, ReasoningTrace,
# NarrativeReport, etc.) — mirrors spec/support/analysis_factories.rb's
# philosophy: only the attributes formatter code actually reads get a
# meaningful default, everything else is a neutral filler value.
module FormatterFactories
  def build_premise(type: "lexical_choice", source: "token:3", value: "must", weight: 0.7)
    SFL::Core::Types::Premise.new(type:, source:, value:, weight:)
  end

  # rubocop:disable Metrics/ParameterLists -- one flat ReasoningTrace builder; every kwarg maps
  # 1:1 to a real attribute a formatter spec needs to vary independently.
  def build_reasoning_trace(
    premises: [build_premise], inference_rule: "modal_verb_strength", conclusion: { modality: 0.8 },
    confidence: 0.85, derivation_hash: "deadbeef", generated_at: Time.now
  )
    SFL::Core::Types::ReasoningTrace.new(premises:, inference_rule:, conclusion:, confidence:, derivation_hash:,
      generated_at:)
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists -- one flat NarrativeReport builder; every kwarg maps
  # 1:1 to a real attribute a formatter spec needs to vary independently.
  def build_narrative_report(
    source: "conv-1", generated_at: Time.now, overview: "An overview.", cast_and_roles: "Cast notes.",
    interpersonal_dynamics: "Dynamics notes.", conversational_arc: "Arc notes.",
    data_quality: "Data quality notes.", takeaways: "Takeaway notes."
  )
    SFL::Core::Types::NarrativeReport.new(
      source:, generated_at:, overview:, cast_and_roles:, interpersonal_dynamics:,
      conversational_arc:, data_quality:, takeaways:
    )
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists -- one flat KnowledgeArtifact builder covering every
  # field kb_*_formatter specs need to vary independently; splitting it would just relocate kwargs.
  def build_knowledge_artifact(
    artifact_id: 1, title: "Introduction", source_file: "docs/guide.md", section_path: "Introduction",
    content_type: :technical_reference, quality_score: 0.7, migration_action: :keep,
    migration_reason: "high quality, current", tags: [], last_updated: Time.now, clauses: [],
    avg_tenor: 0.6, avg_modality: 0.6, dominant_mood: "declarative", process_types: {},
    annotation_coverage: {}
  )
    SFL::Core::Types::KnowledgeArtifact.new(
      artifact_id:, title:, source_file:, section_path:, content_type:, quality_score:,
      migration_action:, migration_reason:, tags:, last_updated:, clauses:, avg_tenor:,
      avg_modality:, dominant_mood:, process_types:, annotation_coverage:
    )
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists -- one flat MigrationManifestEntry builder; every kwarg
  # maps 1:1 to a real attribute a formatter spec needs to vary independently.
  def build_migration_manifest_entry(
    artifact_id: 1, title: "Introduction", source_file: "docs/guide.md", action: :keep,
    reason: "high quality, current", quality_score: 0.7, content_type: :technical_reference
  )
    SFL::Core::Types::MigrationManifestEntry.new(artifact_id:, title:, source_file:, action:, reason:, quality_score:,
      content_type:)
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists -- one flat KnowledgeBaseReport builder; every kwarg
  # maps 1:1 to a real attribute a kb formatter/report-writer spec needs to vary independently.
  def build_knowledge_base_report(
    metadata: {}, artifacts: [], migration_manifest: [], content_type_distribution: {},
    quality_distribution: {}, staleness_flags: []
  )
    SFL::Core::Types::KnowledgeBaseReport.new(
      metadata:, artifacts:, migration_manifest:, content_type_distribution:, quality_distribution:, staleness_flags:
    )
  end
  # rubocop:enable Metrics/ParameterLists
end

RSpec.configure do |config|
  config.include AnalysisFactories, file_path: %r{spec/formatters}
  config.include FormatterFactories, file_path: %r{spec/formatters}
end
