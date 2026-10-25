# frozen_string_literal: true

require "spec_helper"

# The composition root builds TopicModeler's factory in CLI.build_conversation_engine. These examples
# capture the factory Engine receives and call it with a stubbed TopicModeler, so no sidecar spawns.
RSpec.describe SFL::CLI, ".build_conversation_engine topic modeler factory" do
  let(:embedder) { instance_double(SFL::LLM::Embedder) }
  let(:sidecar_command) { ["/opt/py/bin/python", "/repo/sidecar/bertopic/bertopic_sidecar.py"] }
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: nil, embedder:, bertopic_command: sidecar_command, topic_speaker_names: ["Alice"],
      embedder_info: { provider: "ollama", model: "embeddinggemma", endpoint: "http://tinybot:11434" }
    )
  end
  let(:logger) { SFL::Core::Ports::Null::Logger.new }
  let(:modeler) { instance_double(SFL::Analysis::TopicModeler) }
  let(:options) { { store: false, pass1_only: false, resume: false, topics: 3 } }

  before do
    allow(SFL::Boot).to receive(:logger).and_return(logger)
    allow(described_class).to receive(:build_pipeline).and_return(instance_double(SFL::Core::Pipeline))
    allow(SFL::Analysis::TopicModeler).to receive(:new).and_return(modeler)
  end

  # Returns the topic_modeler_factory that build_conversation_engine handed to Analysis::Engine.new.
  def factory_from_engine(boot = boot_result)
    captured = nil
    allow(SFL::Analysis::Engine).to receive(:new) do |**kwargs|
      captured = kwargs[:topic_modeler_factory]
      instance_double(SFL::Analysis::Engine)
    end
    described_class.build_conversation_engine(boot, options, instance_double(SFL::CLI::StopFlag, stopped?: false))
    captured
  end

  it "builds TopicModeler with the sidecar command, embedder and speaker names from Boot" do
    factory = factory_from_engine

    expect(factory.call(k: nil)).to eq(modeler)
    expect(SFL::Analysis::TopicModeler).to have_received(:new).with(
      embedder:, sidecar_command:, k: nil, speaker_names: ["Alice"], logger:,
      embedder_info: { provider: "ollama", model: "embeddinggemma", endpoint: "http://tinybot:11434" }
    )
  end

  it "passes the requested nr_topics through as k" do
    factory = factory_from_engine

    factory.call(k: 5)

    expect(SFL::Analysis::TopicModeler).to have_received(:new).with(hash_including(k: 5))
  end

  it "wires no topic model store, so fits are not persisted" do
    factory_from_engine.call(k: nil)

    expect(SFL::Analysis::TopicModeler).to have_received(:new).with(hash_not_including(:store, :collection_key))
  end

  it "defaults speaker_names and embedder_info when Boot leaves them unset" do
    bare = SFL::Boot::Result.new(db: nil, embedder:, bertopic_command: sidecar_command)

    factory_from_engine(bare).call(k: nil)

    expect(SFL::Analysis::TopicModeler).to have_received(:new).with(hash_including(speaker_names: [], embedder_info: {}))
  end

  it "raises a clear error at factory call when no embedder was built (--pass1-only)" do
    no_embedder = SFL::Boot::Result.new(db: nil, embedder: nil, bertopic_command: sidecar_command)
    factory = factory_from_engine(no_embedder)

    expect { factory.call(k: nil) }
      .to raise_error(SFL::Analysis::Error, /--topics needs the embedding task/)
    expect(SFL::Analysis::TopicModeler).not_to have_received(:new)
  end
end
