# frozen_string_literal: true

require "spec_helper"

# Facts 58 and 59: env var, then task_models row, then default.
RSpec.describe SFL::Boot::TaskModelResolver do
  let(:env) do
    {
      "SFL_TASK_PASS_TWO_ANNOTATION_MODEL" => "env/model",
      "SFL_TASK_PASS_TWO_ANNOTATION_TEMPERATURE" => "0.2",
      "SFL_TASK_EMBEDDING_MODEL" => "embeddinggemma:latest",
    }
  end
  let(:store) do
    SFL::Core::Ports::Fake::ModelStore.new(assignments: {
      pass_two_annotation: { provider: "openrouter", model_id: "db/ignored" },
      pass_two_batch_annotation: { provider: "openrouter", model_id: "db/batch" },
      loader_drafting: { provider: "mistral", model_id: "db/drafter" },
    })
  end

  def resolved(resolver) = resolver.resolve.transform_values { |res| [res.provider, res.model, res.source, res.env_var] }

  it "takes the env var when set, else the task_models row, else the default (fact 58)" do
    expect(resolved(described_class.new(env:, store:))).to eq(
      pass_two_annotation: [:openrouter, "env/model", :env, "SFL_TASK_PASS_TWO_ANNOTATION_MODEL"],
      pass_two_batch_annotation: [:openrouter, "db/batch", :db, nil],
      context_synthesis: [:openrouter, "env/model", :default, nil],
      narrative_generation: [:openrouter, "env/model", :default, nil],
      embedding: [:ollama, "embeddinggemma:latest", :env, "SFL_TASK_EMBEDDING_MODEL"],
      ingest_classification: [:ollama, "embeddinggemma:latest", :default, nil],
      loader_drafting: [:mistral, "db/drafter", :db, nil]
    )
  end

  it "resolves from env and defaults only without a store (fact 59)" do
    resolutions = described_class.new(env:).resolve

    expect(resolutions.values.map(&:source).uniq).to contain_exactly(:env, :default)
    expect(resolutions[:pass_two_batch_annotation]).to have_attributes(provider: :openrouter,
      model: "google/gemma-4-26b-a4b-it:free", source: :default)
  end

  it "defaults every LLM task with no override to the free OpenRouter gemma model" do
    llm_tasks = described_class.new(env: {}).resolve.except(:embedding, :ingest_classification)

    expect(llm_tasks.values).to all(have_attributes(provider: :openrouter, model: "google/gemma-4-26b-a4b-it:free",
      source: :default))
  end

  it "keeps the embedding default and the derived ingest_classification default unchanged" do
    resolutions = described_class.new(env: {}).resolve

    expect(resolutions[:embedding]).to have_attributes(provider: :ollama, model: "embeddinggemma-2:440m", source: :default)
    expect(resolutions[:ingest_classification]).to have_attributes(provider: :ollama, model: "embeddinggemma-2:440m")
  end

  it "ignores the legacy EMBEDDING_MODEL and EMBEDDING_PROVIDER names for the embedding task" do
    resolver = described_class.new(env: { "EMBEDDING_MODEL" => "legacy", "EMBEDDING_PROVIDER" => "mistral" })

    expect(resolver.resolve[:embedding]).to have_attributes(provider: :ollama, model: "embeddinggemma-2:440m",
      source: :default, env_var: nil)
  end

  it "takes SFL_TASK_EMBEDDING_MODEL over the embeddinggemma-2:440m default" do
    resolver = described_class.new(env: { "SFL_TASK_EMBEDDING_MODEL" => "new-model" })

    expect(resolver.resolve[:embedding]).to have_attributes(model: "new-model", source: :env,
      env_var: "SFL_TASK_EMBEDDING_MODEL")
  end

  it "keeps the env provider and params whatever the source" do
    resolver = described_class.new(env: env.merge("SFL_TASK_LOADER_DRAFTING_PROVIDER" => "gemini",
      "SFL_TASK_LOADER_DRAFTING_MAX_TOKENS" => "9"), store: SFL::Core::Ports::Fake::ModelStore.new)

    expect(resolver.resolve[:loader_drafting]).to have_attributes(provider: :gemini, model: "env/model", source: :default,
      params: { max_tokens: 9 })
    expect(resolver.resolve[:pass_two_annotation].params).to eq(temperature: 0.2)
  end

  it "builds an LLM::Config whose TaskConfigs carry the source" do
    config = described_class.new(env:, store:).call

    expect(config.for(:pass_two_batch_annotation)).to have_attributes(model: "db/batch", source: :db, env_var: nil)
    expect(config.for(:pass_two_annotation)).to have_attributes(source: :env, env_var: "SFL_TASK_PASS_TWO_ANNOTATION_MODEL")
  end

  it "raises Boot::Error when the store cannot be read" do
    broken = instance_double(SFL::Store::PgModelRepository)
    allow(broken).to receive(:assignments).and_raise(Sequel::DatabaseError, "relation does not exist")

    expect { described_class.new(env:, store: broken).resolve }
      .to raise_error(SFL::Boot::Error, /cannot read task_models.*relation does not exist/)
  end

  it "names the capability each task needs" do
    expect([described_class.capability(:embedding), described_class.capability("loader_drafting")]).to eq(%w[embedding chat])
  end

  it "tags each resolution with its task, whatever the source" do
    resolutions = described_class.new(env:, store:).resolve

    expect(resolutions.map { |task, res| [task, res.task] }).to all(satisfy { |task, own| task == own })
    expect(resolutions.values.map(&:source).uniq).to contain_exactly(:env, :db, :default)
  end

  it "uses the env provider together with the env model, and ignores blank env values" do
    resolver = described_class.new(env: env.merge("SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER" => "gemini",
      "SFL_TASK_LOADER_DRAFTING_MODEL" => "  ", "SFL_TASK_CONTEXT_SYNTHESIS_PROVIDER" => " "), store:)
    resolutions = resolver.resolve

    expect(resolutions[:pass_two_annotation]).to have_attributes(provider: :gemini, model: "env/model", source: :env)
    expect(resolutions[:loader_drafting]).to have_attributes(provider: :mistral, model: "db/drafter", source: :db)
    expect(resolutions[:context_synthesis]).to have_attributes(provider: :gemini, source: :default)
  end

  it "names the failing error's class and message" do
    broken = instance_double(SFL::Store::PgModelRepository)
    allow(broken).to receive(:assignments).and_raise(Sequel::DatabaseError, "relation does not exist")

    expect { described_class.new(env:, store: broken).resolve }.to raise_error(SFL::Boot::Error,
      "cannot read task_models (run rake db:migrate?): Sequel::DatabaseError: relation does not exist")
  end

  it "accepts a task name given as a string" do
    expect(described_class.capability("embedding")).to eq("embedding")
  end
end
